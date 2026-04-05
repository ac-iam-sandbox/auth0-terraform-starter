/**
 * Action: Enrich Tokens with gen_locale, soldto, shipto
 * Trigger: Post Login
 */

const NS = "https://claims.myalcon.com/";

/**
 * Compute gen_locale in the format language_COUNTRY
 * Example: ja + JP => ja_JP
 */
function computeGenLocale(language, country) {
  const lang = (language || "en").toLowerCase();
  if (country) return `${lang}_${country.toUpperCase()}`;
  return lang;
}

exports.onExecutePostLogin = async (event, api) => {
  const userMeta = event.user.user_metadata || {};
  const query = event.request?.query || {};

  // --------------------------------------------
  // 1. READ LANGUAGE & COUNTRY
  // --------------------------------------------
  const language =
    userMeta.language ||
    event.transaction?.locale ||
    "en";

  const country =
    userMeta.country ||
    userMeta.country_code ||
    null;

  // --------------------------------------------
  // 2. COMPUTE gen_locale (lang_COUNTRY)
  // --------------------------------------------
  const genLocale = computeGenLocale(language, country);

  // --------------------------------------------
  // 3. SAVE gen_locale to user_metadata
  // --------------------------------------------
  api.user.setUserMetadata("gen_locale", genLocale);

  // --------------------------------------------
  // 4. READ soldto / shipto
  // --------------------------------------------
  const soldto = query["ext-soldto"] || userMeta.soldto || null;
  const shipto = query["ext-shipto"] || userMeta.shipto || null;

  if (query["ext-soldto"]) api.user.setUserMetadata("soldto", query["ext-soldto"]);
  if (query["ext-shipto"]) api.user.setUserMetadata("shipto", query["ext-shipto"]);

  // --------------------------------------------
  // 5. ADD CLAIMS TO ID TOKEN
  // --------------------------------------------
  api.idToken.setCustomClaim(`${NS}gen_locale`, genLocale);

  if (soldto) api.idToken.setCustomClaim(`${NS}soldto`, soldto);
  if (shipto) api.idToken.setCustomClaim(`${NS}shipto`, shipto);

  // --------------------------------------------
  // 6. ADD CLAIMS TO ACCESS TOKEN
  // --------------------------------------------
  api.accessToken.setCustomClaim(`${NS}gen_locale`, genLocale);

  if (soldto) api.accessToken.setCustomClaim(`${NS}soldto`, soldto);
  if (shipto) api.accessToken.setCustomClaim(`${NS}shipto`, shipto);
};
