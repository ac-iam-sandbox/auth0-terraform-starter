/**
 * Action:  Email Verification
 * Trigger: Post Login
 * Order:   Before "Complete Social Profile" in the Post Login flow
 *
 * Checks if the user logged in via a Username-Password (auth0) database
 * connection. If their email is NOT verified (either root-level or via
 * account linking), renders a verification form.
 *
 * Secrets:
 *   - FORM_ID
 */

const CONNECTION_LABELS = {
  "auth0": "Email",
  "google-oauth2": "Google",
  "apple": "Apple",
  "line": "Line",
};

exports.onExecutePostLogin = async (event, api) => {
  if (event.connection.strategy !== 'auth0') {
    return;
  }

  if (event.user.email_verified) {
    return;
  }

  const userMeta = event.user.user_metadata || {};
  if (userMeta.email_verified_by_link) {
    return;
  }

  if (event.transaction && event.transaction.protocol === 'oauth2-refresh-token') {
    return;
  }

  if (!event.secrets.FORM_ID) {
    console.error('FORM_ID secret is not configured.');
    return api.access.deny('Invalid configuration: Missing FORM_ID.');
  }

  api.prompt.render(event.secrets.FORM_ID, {
    fields: {
      connection_type: CONNECTION_LABELS[event.connection.strategy] || event.connection.strategy,
    },
  });
};

exports.onContinuePostLogin = async (event, api) => {
  if (!event.user.email_verified) {
    return api.access.deny(
      'Email verification is required to continue. Please verify your email and try again.'
    );
  }
};
