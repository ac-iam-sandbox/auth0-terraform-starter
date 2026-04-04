/**
 * Action:  Enrich Signup Profile
 * Trigger: Pre-User Registration
 *
 * Flow:
 *   Normalize raw form fields to clean keys
 *   Validate with Joi schema
 *   Determine entry path (store | prescription | patient)
 *   Verify entry path against external API
 *   For patient path: verify signup email matches consumer record
 *
 * Module dependencies:
 *   - signup-validation
 *   - entry-path-verification
 */

const {
  extractFields,
  normalizeFields,
  validatePhone,
  validateEntryPath,
  formatErrors,
  buildConsentRecords,
  fields,
  Joi,
  ERRORS,
} = require("actions:signup-validation");

const { verifyEntryPath } = require("actions:entry-path-verification");

const PROFILES = {
  marlo_patient_portal: {
    consentVersion: "1.0",

    fieldMap: [
      { from: "ulp-first-name", to: "first_name" },
      { from: "ulp-last-name", to: "last_name" },
      { from: "ulp-first-name-kana", to: "first_name_kana" },
      { from: "ulp-last-name-kana", to: "last_name_kana" },
      { from: "ulp-gender", to: "gender" },
      { from: "ulp-phone-country", to: "phone_country" },
      { from: "ulp-phone-number", to: "phone_number" },
      { from: "ulp-ext-countrycode", to: "country" },
      { from: "language", to: "language" },
      { from: "ulp-ext-mcode", to: "mcode" },
      { from: "ulp-ext-aid", to: "anonymous_id" },
      { from: "ulp-ext-pdata", to: "pdata" },
      { from: "ulp-ext-shipto", to: "ship_to" },
      { from: "ulp-ext-soldto", to: "sold_to" },
      { from: "ulp-consent-terms-and-privacy", to: "consent_terms" },
      { from: "ulp-consent-health-data", to: "consent_health" },
      { from: "ulp-consent-marketing", to: "consent_marketing" },
    ],

    schema: Joi.object({
      first_name: fields.firstName,
      last_name: fields.lastName,
      first_name_kana: fields.firstNameKana,
      last_name_kana: fields.lastNameKana,
      gender: fields.gender,
      phone_country: fields.phoneCountry,
      phone_number: fields.phoneNumber,
      country: fields.country,
      language: fields.language,
      mcode: fields.optionalString,
      pdata: fields.optionalString,
      ship_to: fields.shipTo,
      sold_to: fields.soldTo,
      anonymous_id: fields.optionalString,
      consent_terms: fields.consentRequired,
      consent_health: fields.consentRequired,
      consent_marketing: fields.consentOptional,
    }).options({ stripUnknown: true, abortEarly: false }),

    consents: [
      { key: "terms_and_privacy", field: "consent_terms" },
      { key: "health_data_processing", field: "consent_health" },
      { key: "marketing", field: "consent_marketing" },
    ],

    entryPaths: [
      { key: "store", fields: ["ship_to", "sold_to"] },
    ],

    userMetadataKeys: [
      "first_name", "last_name", "first_name_kana", "last_name_kana",
      "gender", "country", "language",
    ],

    appMetadataKeys: [
      "mcode", "anonymous_id", "pdata", "ship_to", "sold_to",
    ],
  },
};

exports.onExecutePreUserRegistration = async (event, api) => {
  if (event.connection.strategy !== "auth0") {
    api.user.setUserMetadata("entry_path", "social");
    api.user.setAppMetadata("signup_source", "social");
    api.user.setAppMetadata("registration_completed", false);
    return;
  }

  const profileKey = event.client?.metadata?.signup_profile;
  if (!profileKey) return;

  const profile = PROFILES[profileKey];
  if (!profile) {
    console.log(`Unknown signup_profile: ${profileKey}`);
    return;
  }

  const body = event.request?.body || {};
  const normalized = normalizeFields(body, profile.fieldMap);
  const extracted = extractFields(normalized, profile.schema);
  const { error, value } = profile.schema.validate(extracted);

  if (error) {
    api.validation.error("invalid_payload", formatErrors(error));
    return;
  }

  const phone = validatePhone(value.phone_country, value.phone_number);
  if (!phone.valid) {
    api.validation.error(phone.error.code, phone.error.message);
    return;
  }

  const pathResult = validateEntryPath(profile.entryPaths, value);
  if (!pathResult.valid) {
    api.validation.error(pathResult.error.code, pathResult.error.message);
    return;
  }

  const entryPathKey = pathResult.key;
  const locale = event.transaction?.locale || "en";

  const verification = await verifyEntryPath(entryPathKey, value, {
    baseUrl: event.secrets.API_BASE_URL,
    market: value.country,
    locale,
    anonymousId: value.anonymous_id,
  });

  if (!verification.valid) {
    api.validation.error(verification.error.code, verification.error.message);
    return;
  }

  if (entryPathKey === "patient" && verification.consumer) {
    const consumerEmail = (verification.consumer.email || "").toLowerCase().trim();
    const signupEmail = (event.user?.email || "").toLowerCase().trim();
    if (!consumerEmail || signupEmail !== consumerEmail) {
      console.log("Patient email mismatch: signup email does not match consumer record");
      api.validation.error(ERRORS.PATIENT_EMAIL_MISMATCH.code, ERRORS.PATIENT_EMAIL_MISMATCH.message);
      return;
    }
  }

  for (const key of profile.userMetadataKeys) {
    const v = value[key];
    if (v !== undefined && v !== "") api.user.setUserMetadata(key, v);
  }

  api.user.setUserMetadata("phone", phone.e164);
  api.user.setUserMetadata("locale", `${value.language}_${value.country}`);

  for (const key of profile.appMetadataKeys) {
    const v = value[key];
    if (v !== undefined && v !== "") api.user.setAppMetadata(key, v);
  }

  api.user.setAppMetadata("entry_path", entryPathKey);
  api.user.setAppMetadata("consents", {
    [profileKey]: buildConsentRecords(profile.consents, value, profile.consentVersion),
  });
  api.user.setAppMetadata("signup_source", profileKey);
  api.user.setAppMetadata("registration_completed", true);
};
