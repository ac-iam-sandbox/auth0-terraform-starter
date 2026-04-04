/**
 * Action Module: entry-path-verification
 *
 * Verifies signup entry paths against external APIs.
 *
 * Entry paths:
 *   - prescription : ext-mcode + ext-aid → POST /anonymous/code/check
 *   - patient      : ext-mcode only (no ext-aid) → POST /anonymous/code/check (returns consumer data)
 *   - store        : soldTo + shipTo → GET /anonymous/stores/verify/:soldTo/:shipTo
 */

const ERRORS = {
  VERIFICATION_FAILED: {
    code: "verification_failed",
    message: "We were unable to verify your information. Please try again.",
  },
  VERIFICATION_UNAVAILABLE: {
    code: "verification_service_error",
    message: "Verification is temporarily unavailable. Please try again later.",
  },
};

function isValidE164(phone) {
  if (typeof phone !== "string") return false;
  return /^\+[1-9]\d{4,14}$/.test(phone);
}

function buildUrl(base, path, queryParams = {}) {
  const baseUrl = base.endsWith("/") ? base : base + "/";
  const normalizedPath = path.startsWith("/") ? path.substring(1) : path;
  const url = new URL(baseUrl + normalizedPath);
  for (const [key, value] of Object.entries(queryParams)) {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

async function safeRequest(url, options = {}) {
  try {
    console.log(`Verification API: ${options.method || "GET"} ${url}`);
    const res = await fetch(url, {
      ...options,
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    });
    const textBody = await res.text();
    let jsonBody = null;
    try { jsonBody = textBody ? JSON.parse(textBody) : null; } catch {}
    if (!res.ok) {
      console.log(`Verification API error [${res.status}]: ${textBody || "(empty)"}`);
      return { success: false, status: res.status, response: jsonBody };
    }
    return jsonBody || { success: false };
  } catch (err) {
    console.log(`Verification API network error: ${err.message}`);
    return null;
  }
}

async function verifyMagicCode({ baseUrl, code, market, locale, anonymousId = "" }) {
  if (!code) return { valid: false, error: ERRORS.VERIFICATION_FAILED };
  const url = buildUrl(baseUrl, "/anonymous/code/check", { market, locale });
  const result = await safeRequest(url, {
    method: "POST",
    body: JSON.stringify({ code, anonymousId: anonymousId || "" }),
  });
  if (result === null) return { valid: false, error: ERRORS.VERIFICATION_UNAVAILABLE };
  if (result.success !== true) {
    console.log("Magic code verification failed:", JSON.stringify(result));
    return { valid: false, error: ERRORS.VERIFICATION_FAILED };
  }
  var response = { valid: true };
  if (result.consumer) {
    var consumer = result.consumer;
    var phone = consumer.phoneNumber || null;
    if (phone && !isValidE164(phone)) {
      console.log("Consumer phone failed E.164 format check:", phone);
      phone = null;
    }
    response.consumer = {
      firstName: consumer.firstName || null,
      lastName: consumer.lastName || null,
      email: consumer.email || null,
      firstNameKana: consumer.firstNameKana || null,
      lastNameKana: consumer.lastNameKana || null,
      phoneNumber: phone,
    };
  }
  return response;
}

async function verifyStore({ baseUrl, soldTo, shipTo, market, locale }) {
  if (!soldTo || !shipTo) {
    console.log("Missing soldTo or shipTo for store verification");
    return { valid: false, error: ERRORS.VERIFICATION_FAILED };
  }
  const path = `/anonymous/stores/verify/${encodeURIComponent(soldTo)}/${encodeURIComponent(shipTo)}`;
  const url = buildUrl(baseUrl, path, { market, locale });
  const result = await safeRequest(url, { method: "GET" });
  if (result === null) return { valid: false, error: ERRORS.VERIFICATION_UNAVAILABLE };
  if (result.isValid !== true) {
    console.log("Store verification failed:", JSON.stringify(result));
    return { valid: false, error: ERRORS.VERIFICATION_FAILED };
  }
  return { valid: true };
}

async function verifyEntryPath(pathKey, values, options) {
  const { baseUrl, market, locale } = options;
  try {
    switch (pathKey) {
      case "prescription":
        return verifyMagicCode({ baseUrl, code: values.mcode, market, locale, anonymousId: options.anonymousId });
      case "patient":
        return verifyMagicCode({ baseUrl, code: values.mcode, market, locale });
      case "store":
        return verifyStore({ baseUrl, soldTo: values.sold_to, shipTo: values.ship_to, market, locale });
      default:
        console.log("Unknown entry path:", pathKey);
        return { valid: false, error: ERRORS.VERIFICATION_FAILED };
    }
  } catch (err) {
    console.log("Verification pipeline error:", err.message);
    return { valid: false, error: ERRORS.VERIFICATION_UNAVAILABLE };
  }
}

module.exports = { ERRORS, verifyEntryPath };
