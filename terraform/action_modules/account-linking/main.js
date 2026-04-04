/**
 * Action Module: account-linking
 *
 * Shared utilities for account linking and Management API access.
 * Used by both the Complete Social Profile and Link Accounts actions.
 *
 * Dependencies: auth0
 * Secrets: MANAGEMENT_API_DOMAIN, MANAGEMENT_API_CLIENT_ID, MANAGEMENT_API_CLIENT_SECRET
 */

const { AuthenticationClient } = require("auth0");

var TTL_LEEWAY_FACTOR = 0.2;
var REQUEST_TIMEOUT_MS = 5000;
var LINKING_DONE_KEY = "account_linking_completed";
var LINKING_PERFORMED = "linking_performed";

var DATABASE_STRATEGIES = new Set(["auth0"]);
var SOCIAL_STRATEGIES = new Set(["google-oauth2", "apple", "line"]);

var CONNECTION_LABELS = {
  "auth0": "Email",
  "google-oauth2": "Google",
  "apple": "Apple",
  "line": "Line",
};

var PRIMARY_ONLY_APP_KEYS = new Set([
  "registration_completed", "signup_source", "registered_at",
  LINKING_DONE_KEY, "linked_at", "linking_cancelled_at",
]);

var PRIMARY_ONLY_USER_KEYS = new Set(["email"]);

function connectionLabel(strategy) { return CONNECTION_LABELS[strategy] || strategy; }

function resolveEmail(event) {
  var email = event.user.email;
  if (!email && event.user.user_metadata) email = event.user.user_metadata.email;
  return email ? email.toLowerCase().trim() : null;
}

function resolveCandidateEmail(candidate) {
  var email = candidate.email;
  if (!email && candidate.user_metadata) email = candidate.user_metadata.email;
  return email ? email.toLowerCase().trim() : null;
}

function isEmailTrusted(user, strategy) {
  if (DATABASE_STRATEGIES.has(strategy)) return user.email_verified === true;
  return true;
}

function isKnownStrategy(strategy) { return DATABASE_STRATEGIES.has(strategy) || SOCIAL_STRATEGIES.has(strategy); }
function isDatabaseStrategy(strategy) { return DATABASE_STRATEGIES.has(strategy); }
function isRegistrationCompleted(candidate) { return (candidate.app_metadata || {}).registration_completed === true; }

function extractRawId(userId) {
  if (!userId) return userId;
  var parts = userId.split("|");
  return parts.length > 1 ? parts.slice(1).join("|") : userId;
}

function findAllLinkCandidates(users, currentUserId, email) {
  var normalizedEmail = email.toLowerCase();
  return users.filter(function (u) {
    if (u.user_id === currentUserId) return false;
    if (!u.identities || !u.identities.length) return false;
    var primaryStrategy = u.identities[0].provider;
    if (!isKnownStrategy(primaryStrategy)) return false;
    if (!isEmailTrusted(u, primaryStrategy)) return false;
    var candidateEmail = resolveCandidateEmail(u);
    if (!candidateEmail || candidateEmail !== normalizedEmail) return false;
    if (!isRegistrationCompleted(u)) return false;
    return true;
  });
}

function buildLinkPlan(event, candidates) {
  var allAccounts = [];
  allAccounts.push({ user_id: event.user.user_id, provider: event.connection.strategy, created_at: new Date(event.user.created_at || Date.now()) });
  for (var i = 0; i < candidates.length; i++) {
    allAccounts.push({ user_id: candidates[i].user_id, provider: candidates[i].identities[0].provider, created_at: new Date(candidates[i].created_at) });
  }
  allAccounts.sort(function (a, b) {
    var aIsDb = DATABASE_STRATEGIES.has(a.provider) ? 0 : 1;
    var bIsDb = DATABASE_STRATEGIES.has(b.provider) ? 0 : 1;
    if (aIsDb !== bIsDb) return aIsDb - bIsDb;
    return a.created_at.getTime() - b.created_at.getTime();
  });
  return { primary: allAccounts[0], secondaries: allAccounts.slice(1) };
}

async function getManagementToken(api) {
  var domain = actions.secrets.MANAGEMENT_API_DOMAIN;
  var clientId = actions.secrets.MANAGEMENT_API_CLIENT_ID;
  var clientSecret = actions.secrets.MANAGEMENT_API_CLIENT_SECRET;
  var cacheKey = "mgmt-token-" + clientId;
  var cached = api.cache.get(cacheKey);
  if (cached && cached.value) return cached.value;
  var auth = new AuthenticationClient({ domain: domain, clientId: clientId, clientSecret: clientSecret });
  var result = await auth.oauth.clientCredentialsGrant({ audience: "https://" + domain + "/api/v2/" });
  var accessToken = result.data.access_token;
  var expiresIn = result.data.expires_in;
  api.cache.set(cacheKey, accessToken, { ttl: Math.floor(expiresIn - expiresIn * TTL_LEEWAY_FACTOR) });
  return accessToken;
}

async function mgmtApiRequest(api, method, path, body) {
  var token = await getManagementToken(api);
  var url = "https://" + actions.secrets.MANAGEMENT_API_DOMAIN + "/api/v2" + path;
  var options = { method: method, headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" }, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) };
  if (body) options.body = JSON.stringify(body);
  var res = await fetch(url, options);
  var data = await res.json();
  if (res.status < 200 || res.status >= 300) throw new Error(method + " " + path + " (" + res.status + ")");
  return data;
}

async function searchUsersByEmail(api, email) {
  var fields = "user_id,email,email_verified,identities,user_metadata,app_metadata,created_at";
  var byEmailParams = new URLSearchParams({ email: email, fields: fields, include_fields: "true" });
  var escapedEmail = email.replace(/([+\-&|!(){}[\]^"~*?:\\/])/g, "\\$1");
  var luceneQuery = 'user_metadata.email:"' + escapedEmail + '"';
  var byMetadataParams = new URLSearchParams({ q: luceneQuery, search_engine: "v3", fields: fields, include_fields: "true" });
  var results = await Promise.all([
    mgmtApiRequest(api, "GET", "/users-by-email?" + byEmailParams.toString()),
    mgmtApiRequest(api, "GET", "/users?" + byMetadataParams.toString()),
  ]);
  var seen = new Set();
  var allUsers = [];
  var combined = (results[0] || []).concat(results[1] || []);
  for (var i = 0; i < combined.length; i++) {
    var u = combined[i];
    if (u && u.user_id && !seen.has(u.user_id)) { seen.add(u.user_id); allUsers.push(u); }
  }
  return allUsers;
}

async function linkAccountToTarget(api, primaryUserId, secondaryProvider, secondaryUserId) {
  return mgmtApiRequest(api, "POST", "/users/" + encodeURIComponent(primaryUserId) + "/identities", { provider: secondaryProvider, user_id: extractRawId(secondaryUserId) });
}

function mergeConsents(primaryConsents, secondaryConsents) {
  if (!secondaryConsents) return primaryConsents || {};
  if (!primaryConsents) return secondaryConsents;
  var merged = {};
  var allProfiles = new Set(Object.keys(primaryConsents).concat(Object.keys(secondaryConsents)));
  allProfiles.forEach(function (profileKey) {
    var primaryProfile = primaryConsents[profileKey] || {};
    var secondaryProfile = secondaryConsents[profileKey] || {};
    var mergedProfile = {};
    var allConsentKeys = new Set(Object.keys(primaryProfile).concat(Object.keys(secondaryProfile)));
    allConsentKeys.forEach(function (consentKey) {
      var primary = primaryProfile[consentKey];
      var secondary = secondaryProfile[consentKey];
      if (!primary) { mergedProfile[consentKey] = secondary; }
      else if (!secondary) { mergedProfile[consentKey] = primary; }
      else {
        var primaryTime = new Date(primary.timestamp || 0).getTime();
        var secondaryTime = new Date(secondary.timestamp || 0).getTime();
        mergedProfile[consentKey] = secondaryTime < primaryTime ? secondary : primary;
      }
    });
    merged[profileKey] = mergedProfile;
  });
  return merged;
}

async function mergeMetadataIntoPrimary(api, primaryUserId, primaryUser, secondaryUsers) {
  var primaryAppMeta = primaryUser.app_metadata || {};
  var primaryUserMeta = primaryUser.user_metadata || {};
  var mergedAppMeta = Object.assign({}, primaryAppMeta);
  var mergedUserMeta = Object.assign({}, primaryUserMeta);
  for (var i = 0; i < secondaryUsers.length; i++) {
    var secondary = secondaryUsers[i];
    var secAppMeta = secondary.app_metadata || {};
    var secUserMeta = secondary.user_metadata || {};
    var appKeys = Object.keys(secAppMeta);
    for (var j = 0; j < appKeys.length; j++) {
      var key = appKeys[j];
      if (PRIMARY_ONLY_APP_KEYS.has(key)) continue;
      if (key === "consents") { mergedAppMeta.consents = mergeConsents(mergedAppMeta.consents, secAppMeta.consents); continue; }
      if (mergedAppMeta[key] === undefined || mergedAppMeta[key] === "") mergedAppMeta[key] = secAppMeta[key];
    }
    var userKeys = Object.keys(secUserMeta);
    for (var k = 0; k < userKeys.length; k++) {
      var uKey = userKeys[k];
      if (PRIMARY_ONLY_USER_KEYS.has(uKey)) continue;
      if (mergedUserMeta[uKey] === undefined || mergedUserMeta[uKey] === "") mergedUserMeta[uKey] = secUserMeta[uKey];
    }
  }
  var appMetaChanged = JSON.stringify(mergedAppMeta) !== JSON.stringify(primaryAppMeta);
  var userMetaChanged = JSON.stringify(mergedUserMeta) !== JSON.stringify(primaryUserMeta);
  if (!appMetaChanged && !userMetaChanged) { console.log("No metadata merge needed"); return; }
  var patchBody = {};
  if (appMetaChanged) patchBody.app_metadata = mergedAppMeta;
  if (userMetaChanged) patchBody.user_metadata = mergedUserMeta;
  await mgmtApiRequest(api, "PATCH", "/users/" + encodeURIComponent(primaryUserId), patchBody);
}

async function executeLinkPlan(api, plan, options) {
  var allUsers = (options && options.allUsers) || [];
  var linked = 0;
  var errors = [];
  if (allUsers.length > 0) {
    try {
      var primaryUser = null;
      var secondaryUsers = [];
      for (var u = 0; u < allUsers.length; u++) { if (allUsers[u].user_id === plan.primary.user_id) primaryUser = allUsers[u]; }
      for (var s = 0; s < plan.secondaries.length; s++) { for (var a = 0; a < allUsers.length; a++) { if (allUsers[a].user_id === plan.secondaries[s].user_id) { secondaryUsers.push(allUsers[a]); break; } } }
      if (primaryUser && secondaryUsers.length > 0) await mergeMetadataIntoPrimary(api, plan.primary.user_id, primaryUser, secondaryUsers);
    } catch (err) { console.log("Metadata merge warning:", err && err.message ? err.message : "error"); }
  }
  for (var i = 0; i < plan.secondaries.length; i++) {
    var secondary = plan.secondaries[i];
    try {
      var result = await linkAccountToTarget(api, plan.primary.user_id, secondary.provider, secondary.user_id);
      if (Array.isArray(result) && result.length > 1) linked++;
      else errors.push(secondary.user_id + ": bad response");
    } catch (err) { errors.push(secondary.user_id + ": " + (err && err.message ? err.message : "error")); }
  }
  return { linked: linked, errors: errors };
}

module.exports = {
  LINKING_DONE_KEY: LINKING_DONE_KEY, LINKING_PERFORMED: LINKING_PERFORMED,
  connectionLabel: connectionLabel, resolveEmail: resolveEmail, isDatabaseStrategy: isDatabaseStrategy,
  findAllLinkCandidates: findAllLinkCandidates, buildLinkPlan: buildLinkPlan,
  searchUsersByEmail: searchUsersByEmail, executeLinkPlan: executeLinkPlan,
};
