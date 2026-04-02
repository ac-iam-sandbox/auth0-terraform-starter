/**
 * Shared utility functions for Auth0 Actions.
 *
 * This module is published as an Auth0 Action Module and can be
 * imported by any action that needs common helper functions.
 */

/**
 * Format a user's display name from available fields.
 */
export function formatDisplayName(
  givenName?: string,
  familyName?: string,
  email?: string
): string {
  if (givenName && familyName) {
    return `${givenName} ${familyName}`;
  }
  if (givenName) return givenName;
  if (familyName) return familyName;
  if (email) return email.split('@')[0];
  return 'Unknown User';
}

/**
 * Check if a string is a valid email address.
 */
export function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Safely parse JSON with a fallback default.
 */
export function safeJsonParse<T>(json: string, fallback: T): T {
  try {
    return JSON.parse(json) as T;
  } catch {
    return fallback;
  }
}
