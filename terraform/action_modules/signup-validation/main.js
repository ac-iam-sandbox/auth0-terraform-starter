/**
 * Action Module: signup-validation
 *
 * Shared validation utilities for signup-related Actions.
 * Reusable across multiple signup profiles and triggers.
 *
 * Dependencies: joi, libphonenumber-js
 */

const Joi = require("joi");
const { parsePhoneNumberFromString } = require("libphonenumber-js");

const ERRORS = {
  FIRST_NAME_REQUIRED: { code: "first_name_required", message: "First name is required." },
  FIRST_NAME_INVALID: { code: "first_name_invalid", message: "First name contains invalid characters." },
  FIRST_NAME_TOO_LONG: { code: "first_name_too_long", message: "First name must not exceed 50 characters." },
  LAST_NAME_REQUIRED: { code: "last_name_required", message: "Last name is required." },
  LAST_NAME_INVALID: { code: "last_name_invalid", message: "Last name contains invalid characters." },
  LAST_NAME_TOO_LONG: { code: "last_name_too_long", message: "Last name must not exceed 50 characters." },
  KANA_REQUIRED: { code: "kana_required", message: "Kana name is required." },
  KANA_INVALID: { code: "kana_invalid", message: "Kana name contains invalid characters." },
  KANA_TOO_LONG: { code: "kana_too_long", message: "Kana name must not exceed 50 characters." },
  GENDER_REQUIRED: { code: "gender_required", message: "Gender selection is required." },
  GENDER_INVALID: { code: "gender_invalid", message: "Please select a valid gender option." },
  PHONE_COUNTRY_REQUIRED: { code: "phone_country_required", message: "Phone country code is required." },
  PHONE_COUNTRY_INVALID: { code: "phone_country_invalid", message: "Please select a valid phone country code." },
  PHONE_REQUIRED: { code: "phone_required", message: "Phone number is required." },
  PHONE_DIGITS_INVALID: { code: "phone_digits_invalid", message: "Phone number must be between 4 and 15 digits." },
  PHONE_INVALID: { code: "phone_invalid", message: "Phone number is not valid for the selected country." },
  CONSENT_REQUIRED: { code: "consent_required", message: "You must accept all required agreements to continue." },
  COUNTRY_REQUIRED: { code: "country_required", message: "Country is required." },
  COUNTRY_INVALID: { code: "country_invalid", message: "Please provide a valid 2-letter country code." },
  LANGUAGE_REQUIRED: { code: "language_required", message: "Language preference is required." },
  ENTRY_PATH_MISSING: { code: "entry_path_missing", message: "A registration path is required. Please use a valid registration link." },
  ENTRY_PATH_CONFLICT: { code: "entry_path_conflict", message: "Multiple registration paths were detected. Only one is allowed." },
  ENTRY_PATH_INCOMPLETE: { code: "entry_path_incomplete", message: "All fields for the selected registration path are required." },
  SHIP_TO_INVALID: { code: "ship_to_invalid", message: "We were unable to verify your information. Please try again." },
  SOLD_TO_INVALID: { code: "sold_to_invalid", message: "We were unable to verify your information. Please try again." },
  PATIENT_EMAIL_MISMATCH: { code: "patient_email_mismatch", message: "Please use the email address associated with your registration." },
  VALIDATION_FAILED: { code: "validation_failed", message: "Please review your information and try again." },
  VERIFICATION_FAILED: { code: "verification_failed", message: "We were unable to verify your information. Please try again." },
};

function sanitize(value) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/[<>"&]/g, "");
}

function extractFields(body, schema) {
  const expected = Object.keys(schema.describe().keys || {});
  const result = {};
  for (const key of expected) {
    const raw = body[key];
    result[key] = typeof raw === "string" ? sanitize(raw) : raw;
  }
  return result;
}

function normalizeFields(body, fieldMap) {
  const normalized = {};
  for (const { from, to } of fieldMap) {
    const raw = body[from];
    if (raw !== undefined) normalized[to] = typeof raw === "string" ? sanitize(raw) : raw;
  }
  return normalized;
}

function validatePhone(countryDialCode, phoneDigits) {
  const dialCode = String(countryDialCode).split("-")[0];
  const parsed = parsePhoneNumberFromString(dialCode + phoneDigits);
  if (!parsed || !parsed.isValid()) return { valid: false, error: ERRORS.PHONE_INVALID };
  return { valid: true, e164: parsed.format("E.164") };
}

function validateEntryPath(entryPaths, values) {
  var hasMcode = values.mcode !== undefined && values.mcode !== "";
  var hasAnonId = values.anonymous_id !== undefined && values.anonymous_id !== "";
  var storePath = null;
  for (var i = 0; i < entryPaths.length; i++) { if (entryPaths[i].key === "store") { storePath = entryPaths[i]; break; } }
  var hasStoreFields = false;
  if (storePath) hasStoreFields = storePath.fields.some(function (f) { return values[f] !== undefined && values[f] !== ""; });
  if (hasStoreFields && hasMcode) return { valid: false, error: ERRORS.ENTRY_PATH_CONFLICT };
  if (hasMcode) { if (hasAnonId) return { valid: true, key: "prescription" }; return { valid: true, key: "patient" }; }
  if (hasStoreFields) {
    var allStorePresent = storePath.fields.every(function (f) { return values[f] !== undefined && values[f] !== ""; });
    if (!allStorePresent) return { valid: false, error: ERRORS.ENTRY_PATH_INCOMPLETE };
    return { valid: true, key: "store" };
  }
  return { valid: false, error: ERRORS.ENTRY_PATH_MISSING };
}

function formatErrors(error) {
  if (!error?.details?.length) return ERRORS.VALIDATION_FAILED.message;
  const first = error.details[0];
  return first.message?.slice(0, 200) || ERRORS.VALIDATION_FAILED.message;
}

function buildConsentRecords(consents, values, version) {
  const now = new Date().toISOString();
  const records = {};
  for (const c of consents) records[c.key] = { agreed: values[c.field] === "true", version, timestamp: now };
  return records;
}

const NAME_PATTERN = /^[a-zA-ZÀ-ÖØ-öø-ÿ\s'.,-]+$/;
const KANA_PATTERN = /^[\u3000-\u303F\u3040-\u309F\u30A0-\u30FF\uFF00-\uFFEFa-zA-Z\s'.,-]+$/;
const ISO_COUNTRY_PATTERN = /^[A-Z]{2}$/;
const GENDER_VALUES = ["male", "female", "prefer_not_to_say"];

const fields = {
  firstName: Joi.string().trim().min(1).max(50).pattern(NAME_PATTERN).required().messages({ "string.empty": ERRORS.FIRST_NAME_REQUIRED.message, "string.min": ERRORS.FIRST_NAME_REQUIRED.message, "string.max": ERRORS.FIRST_NAME_TOO_LONG.message, "string.pattern.base": ERRORS.FIRST_NAME_INVALID.message, "any.required": ERRORS.FIRST_NAME_REQUIRED.message }),
  lastName: Joi.string().trim().min(1).max(50).pattern(NAME_PATTERN).required().messages({ "string.empty": ERRORS.LAST_NAME_REQUIRED.message, "string.min": ERRORS.LAST_NAME_REQUIRED.message, "string.max": ERRORS.LAST_NAME_TOO_LONG.message, "string.pattern.base": ERRORS.LAST_NAME_INVALID.message, "any.required": ERRORS.LAST_NAME_REQUIRED.message }),
  firstNameKana: Joi.string().trim().min(1).max(50).pattern(KANA_PATTERN).required().messages({ "string.empty": ERRORS.KANA_REQUIRED.message, "string.min": ERRORS.KANA_REQUIRED.message, "string.max": ERRORS.KANA_TOO_LONG.message, "string.pattern.base": ERRORS.KANA_INVALID.message, "any.required": ERRORS.KANA_REQUIRED.message }),
  lastNameKana: Joi.string().trim().min(1).max(50).pattern(KANA_PATTERN).required().messages({ "string.empty": ERRORS.KANA_REQUIRED.message, "string.min": ERRORS.KANA_REQUIRED.message, "string.max": ERRORS.KANA_TOO_LONG.message, "string.pattern.base": ERRORS.KANA_INVALID.message, "any.required": ERRORS.KANA_REQUIRED.message }),
  gender: Joi.string().trim().lowercase().valid(...GENDER_VALUES).required().messages({ "string.empty": ERRORS.GENDER_REQUIRED.message, "any.only": ERRORS.GENDER_INVALID.message, "any.required": ERRORS.GENDER_REQUIRED.message }),
  phoneCountry: Joi.string().trim().pattern(/^\+\d{1,4}/).required().messages({ "string.empty": ERRORS.PHONE_COUNTRY_REQUIRED.message, "string.pattern.base": ERRORS.PHONE_COUNTRY_INVALID.message, "any.required": ERRORS.PHONE_COUNTRY_REQUIRED.message }),
  phoneNumber: Joi.string().trim().pattern(/^\d{4,15}$/).required().messages({ "string.empty": ERRORS.PHONE_REQUIRED.message, "string.pattern.base": ERRORS.PHONE_DIGITS_INVALID.message, "any.required": ERRORS.PHONE_REQUIRED.message }),
  country: Joi.string().trim().uppercase().pattern(ISO_COUNTRY_PATTERN).required().messages({ "string.empty": ERRORS.COUNTRY_REQUIRED.message, "string.pattern.base": ERRORS.COUNTRY_INVALID.message, "any.required": ERRORS.COUNTRY_REQUIRED.message }),
  language: Joi.string().trim().min(1).max(10).required().messages({ "string.empty": ERRORS.LANGUAGE_REQUIRED.message, "any.required": ERRORS.LANGUAGE_REQUIRED.message }),
  consentRequired: Joi.string().valid("true").required().messages({ "any.only": ERRORS.CONSENT_REQUIRED.message, "any.required": ERRORS.CONSENT_REQUIRED.message }),
  consentOptional: Joi.string().optional().allow("").default("false").custom((val) => (val === "true" ? "true" : "false")),
  shipTo: Joi.string().trim().min(9).max(10).optional().allow("").default("").messages({ "string.min": ERRORS.SHIP_TO_INVALID.message, "string.max": ERRORS.SHIP_TO_INVALID.message }),
  soldTo: Joi.string().trim().min(9).max(10).optional().allow("").default("").messages({ "string.min": ERRORS.SOLD_TO_INVALID.message, "string.max": ERRORS.SOLD_TO_INVALID.message }),
  optionalString: Joi.string().trim().max(500).optional().allow("").default(""),
};

module.exports = { ERRORS, sanitize, extractFields, normalizeFields, validatePhone, validateEntryPath, formatErrors, buildConsentRecords, fields, Joi };
