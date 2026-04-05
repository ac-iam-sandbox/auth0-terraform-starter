/**
 * Action: Merge Identity Storage + Email Injection + Last Name Kana Claim
 * Trigger: Post Login
 */

const NAMESPACE = "https://claims.myalcon.com/";

exports.onExecutePostLogin = async (event, api) => {

  //
  // 1. Store identities inside user_metadata
  //
  const identities = event.user.identities || [];
  if (identities.length > 0) {
    api.user.setUserMetadata("auth_identities", identities);
  }

  //
  // 2. Inject email/email_verified into ID & Access Tokens
  //    ONLY if the root user profile has no email
  //
  if (!event.user.email) {
    const meta = event.user.user_metadata || {};
    const email = meta.email || null;
    const email_verified = meta.email_verified || false;

    if (email) {
      api.idToken.setCustomClaim(`${NAMESPACE}email`, email);
      api.idToken.setCustomClaim(`${NAMESPACE}email_verified`, email_verified);

      api.accessToken.setCustomClaim(`${NAMESPACE}email`, email);
      api.accessToken.setCustomClaim(`${NAMESPACE}email_verified`, email_verified);
    }
  }

  //
  // 3. Add Last Name Kana as a custom namespaced ID Token claim
  //
  const userMeta = event.user.user_metadata || {};
  if (userMeta.last_name_kana) {
    api.idToken.setCustomClaim(
      `${NAMESPACE}last_name_kana`,
      userMeta.last_name_kana
    );
  }
};
