/**
 * Action:  Complete Social Profile
 * Trigger: Post Login
 *
 * Flow:
 *   1. Skip database users (handled by pre-registration)
 *   2. Entry path validation + verification (first login only)
 *      - Result stored in transaction metadata
 *      - Valid entry path persisted to app_metadata
 *      - Patient path: consumer data returned from API
 *   3. Account linking check (if email available)
 *      - If candidates found then render linking form
 *      - If linked then merge metadata, trust primary, mark registration complete
 *      - If no candidates + invalid entry path then fail
 *      - If no email (LINE) then skip
 *   4. Progressive profiling (if not yet registered)
 *      - LINE without email: proceeds regardless of entry path result
 *      - Patient path: pre-fills form with consumer data from API
 *
 * Module dependencies:
 *   - signup-validation
 *   - entry-path-verification
 *   - account-linking
 */

const {
  ERRORS,
  sanitize,
  validateEntryPath,
} = require("actions:signup-validation");

const {
  LINKING_DONE_KEY,
  LINKING_PERFORMED,
  connectionLabel,
  resolveEmail,
  isDatabaseStrategy,
  findAllLinkCandidates,
  buildLinkPlan,
  searchUsersByEmail,
  executeLinkPlan,
} = require("actions:account-linking");

const { verifyEntryPath } = require("actions:entry-path-verification");

const TX_ENTRY_PATH_VALID = "entry_path_valid";
const TX_ENTRY_PATH_KEY = "entry_path_key";
const TX_ENTRY_PATH_VERIFIED = "entry_path_verified";
const TX_LINKING_CHECKED = "linking_checked";

const PROFILES = {
  marlo_patient_portal: {
    consentVersion: "1.0",

    entryPaths: [
      { key: "store", fields: ["ship_to", "sold_to"] },
    ],

    queryFieldMap: [
      { from: "ext-countrycode", to: "country" },
      { from: "ext-mcode", to: "mcode" },
      { from: "ext-aid", to: "anonymous_id" },
      { from: "ext-pdata", to: "pdata" },
      { from: "ext-shipto", to: "ship_to" },
      { from: "ext-soldto", to: "sold_to" },
    ],
  },
};

function readParam(query, key) {
  const val = query[key];
  if (Array.isArray(val)) return val[0] || "";
  return typeof val === "string" ? val : "";
}

function normalizeQueryParams(query, fieldMap) {
  const normalized = {};
  for (const { from, to } of fieldMap) {
    const raw = readParam(query, from);
    normalized[to] = typeof raw === "string" ? sanitize(raw) : "";
  }
  return normalized;
}

function parseSocialName(event) {
  let first = event.user.given_name || "";
  let last = event.user.family_name || "";

  if (!first && !last && event.user.name) {
    const parts = event.user.name.trim().split(/\s+/);
    first = parts[0] || "";
    last = parts.slice(1).join(" ") || "";
  }

  const meta = event.user.user_metadata || {};
  if (!first) first = meta.first_name || "";
  if (!last) last = meta.last_name || "";

  return { firstName: first, lastName: last };
}

function denyWithLogout(event, api, errorCode, errorMessage) {
  const appUrl = new URL(event.transaction.redirect_uri);
  appUrl.searchParams.set("error", errorCode);
  appUrl.searchParams.set("error_description", errorMessage);

  const logoutUrl =
    `https://${event.request.hostname}/v2/logout` +
    `?client_id=${event.client.client_id}` +
    `&returnTo=${encodeURIComponent(appUrl.toString())}`;

  api.redirect.sendUserTo(logoutUrl);
}

exports.onExecutePostLogin = async (event, api) => {
  if (isDatabaseStrategy(event.connection.strategy)) return;

  const appMeta = event.user.app_metadata || {};
  const email = resolveEmail(event);
  const registrationCompleted = appMeta.registration_completed === true;
  const linkingSucceeded = !!appMeta[LINKING_DONE_KEY];
  const hasEntryPath = !!appMeta.entry_path;

  if (linkingSucceeded && registrationCompleted) return;

  if (registrationCompleted && hasEntryPath) return;

  const profileKey = event.client?.metadata?.signup_profile;
  if (!profileKey) return;

  const profile = PROFILES[profileKey];
  if (!profile) return;

  if (event.transaction?.protocol === "oauth2-refresh-token") return;

  const query = event.request?.query || {};
  let consumer = null;

  let entryPathIsValid = false;

  if (!appMeta.entry_path) {
    const normalized = normalizeQueryParams(query, profile.queryFieldMap);
    const pathResult = validateEntryPath(profile.entryPaths, normalized);

    if (!pathResult.valid) {
      api.transaction.setMetadata(TX_ENTRY_PATH_VALID, "false");
      console.log("Entry path validation failed:", pathResult.error.code);
    } else {
      const entryPathKey = pathResult.key;

      // Patient path: check email match if social provider gave us an email
      if (entryPathKey === "patient" && email) {
        // We need to verify first to get consumer data, then check email
        // This is handled after verification below
      }

      const locale = event.transaction?.locale || "en";

      const verification = await verifyEntryPath(entryPathKey, normalized, {
        baseUrl: event.secrets.API_BASE_URL,
        market: normalized.country,
        locale,
        anonymousId: normalized.anonymous_id,
      });

      if (!verification.valid) {
        api.transaction.setMetadata(TX_ENTRY_PATH_VALID, "false");
        api.transaction.setMetadata(TX_ENTRY_PATH_KEY, entryPathKey);
        console.log("Entry path verification failed:", verification.error.code);
      } else {
        // Patient path: verify email match if provider gave us an email
        if (entryPathKey === "patient" && verification.consumer) {
          consumer = verification.consumer;

          if (email) {
            const signupEmail = email.toLowerCase().trim();
            const consumerEmail = (consumer.email || "").toLowerCase().trim();

            if (!consumerEmail || signupEmail !== consumerEmail) {
              console.log("Patient email mismatch");
              api.transaction.setMetadata(TX_ENTRY_PATH_VALID, "false");
              denyWithLogout(
                event,
                api,
                ERRORS.PATIENT_EMAIL_MISMATCH.code,
                ERRORS.PATIENT_EMAIL_MISMATCH.message
              );
              return;
            }
          }
        }

        entryPathIsValid = true;

        api.transaction.setMetadata(TX_ENTRY_PATH_VALID, "true");
        api.transaction.setMetadata(TX_ENTRY_PATH_KEY, entryPathKey);
        api.transaction.setMetadata(TX_ENTRY_PATH_VERIFIED, "true");

        api.user.setAppMetadata("entry_path", entryPathKey);

        for (const { to } of profile.queryFieldMap) {
          const v = normalized[to];
          if (v !== undefined && v !== "") {
            api.user.setAppMetadata(to, v);
          }
        }

        const language = event.transaction?.locale || "en";
        const country = normalized.country || "";
        if (country) {
          api.user.setUserMetadata("locale", `${language}_${country}`);
          api.user.setUserMetadata("language", language);
          api.user.setUserMetadata("country", country);
        }
      }
    }
  } else {
    entryPathIsValid = true;
    api.transaction.setMetadata(TX_ENTRY_PATH_VALID, "true");
    api.transaction.setMetadata(TX_ENTRY_PATH_KEY, appMeta.entry_path);
    api.transaction.setMetadata(TX_ENTRY_PATH_VERIFIED, "true");
  }

  if (email) {
    try {
      const allUsers = await searchUsersByEmail(api, email);
      const candidates = findAllLinkCandidates(
        allUsers,
        event.user.user_id,
        email
      );

      if (candidates.length > 0) {
        const plan = buildLinkPlan(event, candidates);
        const labels = candidates.map((c) =>
          connectionLabel(c.identities[0].provider)
        );

        api.prompt.render(event.secrets.LINKING_FORM_ID, {
          fields: {
            email,
            existing_accounts: labels.join(", "),
            account_count: String(candidates.length),
            connection_type: connectionLabel(event.connection.strategy),
          },
          vars: {
            form_type: "linking",
            link_email_used: email,
            link_plan: JSON.stringify({
              primary_user_id: plan.primary.user_id,
              secondaries: plan.secondaries,
            }),
          },
        });
        return;
      }

      api.transaction.setMetadata(TX_LINKING_CHECKED, "true");

      if (!entryPathIsValid) {
        console.log("No link candidates and invalid entry path — denying");
        denyWithLogout(
          event,
          api,
          ERRORS.ENTRY_PATH_MISSING.code,
          ERRORS.ENTRY_PATH_MISSING.message
        );
        return;
      }
    } catch (err) {
      console.log("Link search error:", err.message);
      return;
    }
  }

  if (appMeta.profiling_completed === true) return;

  const name = parseSocialName(event);

  const firstName = consumer?.firstName || name.firstName;
  const lastName = consumer?.lastName || name.lastName;
  const firstNameKana = consumer?.firstNameKana || "";
  const lastNameKana = consumer?.lastNameKana || "";
  const phone = consumer?.phoneNumber || "";
  const profileEmail =
    email || consumer?.email || event.user.user_metadata?.email || "";

  const emailVerified = !!email;

  api.prompt.render(event.secrets.PROFILE_FORM_ID, {
    fields: {
      first_name: String(firstName),
      last_name: String(lastName),
      first_name_kana: String(firstNameKana),
      last_name_kana: String(lastNameKana),
      email: String(profileEmail),
      email_verified: String(emailVerified),
      phone: String(phone),
      has_first_name: String(!!firstName),
      has_last_name: String(!!lastName),
      has_email: String(!!profileEmail),
      connection_type: connectionLabel(event.connection.strategy),
    },
    vars: {
      form_type: "profiling",
    },
  });
};

exports.onContinuePostLogin = async (event, api) => {
  const formType = event.prompt?.vars?.form_type;

  if (formType === "linking") return handleLinking(event, api);
  if (formType === "profiling") return handleProfiling(event, api);
};

async function handleLinking(event, api) {
  const linkEmail = event.prompt?.fields?.link_email;

  if (linkEmail === "false" || linkEmail === false) {
    api.user.setAppMetadata("linking_cancelled_at", new Date().toISOString());

    api.transaction.setMetadata(TX_LINKING_CHECKED, "true");

    denyWithLogout(
      event,
      api,
      "linking_cancelled",
      "Account linking was cancelled. Please try again."
    );
    return;
  }

  if (linkEmail !== "true" && linkEmail !== true) {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  let plan;
  try {
    plan = JSON.parse(event.prompt?.vars?.link_plan || "{}");
  } catch {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  if (!plan.primary_user_id || !plan.secondaries?.length) {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  let allUsers = [];
  const linkEmailUsed = event.prompt?.vars?.link_email_used;
  if (linkEmailUsed) {
    try {
      allUsers = await searchUsersByEmail(api, linkEmailUsed);
      const currentInResults = allUsers.some(
        (u) => u.user_id === event.user.user_id
      );
      if (!currentInResults) {
        allUsers.push({
          user_id: event.user.user_id,
          app_metadata: event.user.app_metadata || {},
          user_metadata: event.user.user_metadata || {},
        });
      }
    } catch (err) {
      console.log("Re-fetch for merge failed:", err.message);
    }
  }

  const result = await executeLinkPlan(
    api,
    {
      primary: { user_id: plan.primary_user_id },
      secondaries: plan.secondaries,
    },
    { allUsers }
  );

  if (result.linked === 0) {
    console.log("Linking failed:", result.errors.join("; "));
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  if (result.errors.length > 0) {
    console.log(
      "Partial link:",
      result.linked,
      "ok,",
      result.errors.length,
      "failed"
    );
  }

  if (event.user.user_id !== plan.primary_user_id) {
    api.authentication.setPrimaryUser(plan.primary_user_id);
  }

  api.transaction.setMetadata(LINKING_PERFORMED, true);
  api.user.setAppMetadata(LINKING_DONE_KEY, Date.now());
  api.user.setAppMetadata("linked_at", new Date().toISOString());
  api.user.setAppMetadata("registration_completed", true);
  api.user.setAppMetadata(
    "signup_source",
    event.client?.metadata?.signup_profile
  );
}

async function handleProfiling(event, api) {
  api.user.setAppMetadata(
    "signup_source",
    event.client?.metadata?.signup_profile
  );
  api.user.setAppMetadata("profiling_completed", true);
  api.user.setAppMetadata("profiled_at", new Date().toISOString());

  const email = resolveEmail(event);
  if (email) {
    try {
      const allUsers = await searchUsersByEmail(api, email);
      const candidates = findAllLinkCandidates(
        allUsers,
        event.user.user_id,
        email
      );

      if (candidates.length > 0) {
        const plan = buildLinkPlan(event, candidates);
        const labels = candidates.map((c) =>
          connectionLabel(c.identities[0].provider)
        );

        api.prompt.render(event.secrets.LINKING_FORM_ID, {
          fields: {
            email,
            existing_accounts: labels.join(", "),
            account_count: String(candidates.length),
            connection_type: connectionLabel(event.connection.strategy),
          },
          vars: {
            form_type: "linking",
            link_email_used: email,
            link_plan: JSON.stringify({
              primary_user_id: plan.primary.user_id,
              secondaries: plan.secondaries,
            }),
          },
        });
        return;
      }
    } catch (err) {
      console.log("Post-profiling link search error:", err.message);
    }

    api.transaction.setMetadata(TX_LINKING_CHECKED, "true");
  }

  const linkingChecked =
    event.transaction?.metadata?.[TX_LINKING_CHECKED] === "true" ||
    !!email;
  const entryPathValid =
    event.transaction?.metadata?.[TX_ENTRY_PATH_VALID] === "true";

  if (linkingChecked && entryPathValid) {
    api.user.setAppMetadata("registration_completed", true);
    api.user.setAppMetadata("registered_at", new Date().toISOString());
  }
}
