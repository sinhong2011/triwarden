import { describe, expect, it } from 'vitest';
import { shouldRequestTotpCopy } from './after-fill';

describe('shouldRequestTotpCopy', () => {
  it('requests copy after fill when the page has no OTP field', () => {
    expect(shouldRequestTotpCopy(false)).toBe(true);
  });

  it('does not auto-copy when an OTP field is on the page', () => {
    expect(shouldRequestTotpCopy(true)).toBe(false);
  });
});
