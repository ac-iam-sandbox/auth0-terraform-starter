/**
 * Action:  Linking Success Notification
 * Trigger: Post Login
 * Order:   After "Complete Social Profile" and "Link Accounts" in the Post Login flow
 *
 * Shows a one-time notification form after account linking completes.
 * Uses transaction metadata (linking_performed) to detect linking in the current flow.
 * Uses app_metadata.linking_notified to ensure it only fires once.
 *
 * Secrets:
 *   - LINKING_SUCCESS_FORM_ID
 */

var PROVIDER_LABELS = {
  "auth0": "Email",
  "google-oauth2": "Google",
  "line": "Line",
  "apple": "Apple",
};

function connectionLabel(provider) {
  return PROVIDER_LABELS[provider] || provider;
}

exports.onExecutePostLogin = async (event, api) => {
  var appMeta = event.user.app_metadata || {};

  // Guard: already notified
  if (appMeta.linking_notified) return;

  // Guard: linking must have occurred in this transaction
  var txMeta = event.transaction && event.transaction.metadata
    ? event.transaction.metadata : {};
  if (!txMeta.linking_performed) return;

  // Guard: skip non-interactive flows
  if (event.transaction && event.transaction.protocol === "oauth2-refresh-token") return;

  var provider = event.connection && event.connection.strategy
    ? event.connection.strategy : "";

  api.prompt.render(event.secrets.LINKING_SUCCESS_FORM_ID, {
    fields: {
      connection_type: connectionLabel(provider),
    },
  });
};

exports.onContinuePostLogin = async (event, api) => {
  // Stamp so we never show again
  api.user.setAppMetadata("linking_notified", Date.now());
};
