import { describe, it, expect } from 'vitest';
import { formatDisplayName, isValidEmail, safeJsonParse } from '../modules/shared-utils';

describe('Shared Utils Module', () => {
  describe('formatDisplayName', () => {
    it('should return full name when both parts are provided', () => {
      expect(formatDisplayName('John', 'Doe')).toBe('John Doe');
    });

    it('should return given name only when family name is missing', () => {
      expect(formatDisplayName('John', undefined)).toBe('John');
    });

    it('should return email prefix when no name is available', () => {
      expect(formatDisplayName(undefined, undefined, 'john@example.com')).toBe('john');
    });

    it('should return Unknown User when nothing is available', () => {
      expect(formatDisplayName()).toBe('Unknown User');
    });
  });

  describe('isValidEmail', () => {
    it('should accept valid emails', () => {
      expect(isValidEmail('user@example.com')).toBe(true);
    });

    it('should reject invalid emails', () => {
      expect(isValidEmail('not-an-email')).toBe(false);
      expect(isValidEmail('@missing.local')).toBe(false);
    });
  });

  describe('safeJsonParse', () => {
    it('should parse valid JSON', () => {
      expect(safeJsonParse('{"a":1}', {})).toEqual({ a: 1 });
    });

    it('should return fallback on invalid JSON', () => {
      expect(safeJsonParse('invalid', { default: true })).toEqual({ default: true });
    });
  });
});
