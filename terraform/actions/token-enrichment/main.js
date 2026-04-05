/**
 * Action: Enrich ID & Access Tokens dynamically with ALL user_metadata
 *         + selected app_metadata fields
 *         + Store consents into user_metadata when provided
 * Trigger: Post Login
 */

const NAMESPACE = "https://claims.myalcon.com/";

/** app_metadata fields to include in the ID token (empty string if missing) */
const APP_META_FIELDS = ["mcode", "anonymous_id", "ship_to", "sold_to"];

/**
 * Recursively add metadata into token as namespaced claims.
 */
function addClaimsRecursivelyToToken(setClaimFn, prefix, data) {
  Object.keys(data).forEach(key => {
    const value = data[key];

    if (value === undefined || value === null) return;

    const claimName = `${prefix}${key}`;

    if (typeof value === "object" && !Array.isArray(value)) {
      addClaimsRecursivelyToToken(setClaimFn, claimName + "/", value);
    } else {
      setClaimFn(claimName, value);
    }
  });
}

exports.onExecutePostLogin = async (event, api) => {
  const userMeta = event.user.user_metadata || {};
  const incomingConsents =
    event.prompt?.fields?.consents ||
    event.request?.body?.consents ||
    event.request?.query?.consents ||
    null;

  if (incomingConsents && typeof incomingConsents === "object") {
    const currentConsents = userMeta.consents || {};

    const mergedConsents = {
      ...currentConsents,
      ...incomingConsents
    };

    api.user.setUserMetadata("consents", mergedConsents);
  }

  const updatedMetadata = event.user.user_metadata || {};

  addClaimsRecursivelyToToken(
    api.idToken.setCustomClaim.bind(api.idToken),
    NAMESPACE,
    updatedMetadata
  );

  addClaimsRecursivelyToToken(
    api.accessToken.setCustomClaim.bind(api.accessToken),
    NAMESPACE,
    updatedMetadata
  );

  const appMeta = event.user.app_metadata || {};

  APP_META_FIELDS.forEach(field => {
    api.idToken.setCustomClaim(
      `${NAMESPACE}${field}`,
      appMeta[field] ?? ""
    );
  });

  // Add app_metadata consents as a single object claim
  api.idToken.setCustomClaim(
    `${NAMESPACE}consents`,
    appMeta.consents ?? {}
  );
};
