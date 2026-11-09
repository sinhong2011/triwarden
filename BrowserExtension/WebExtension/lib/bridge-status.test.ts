import { describe, expect, it } from 'vitest';
import { bridgeDownMessage, isBridgeDown } from './bridge-status';

describe('isBridgeDown', () => {
  it('ignores successful replies and missing answers', () => {
    expect(isBridgeDown(undefined)).toBe(false);
    expect(isBridgeDown({ ok: true })).toBe(false);
    expect(isBridgeDown({ ok: false, error: 'No logins for this site' })).toBe(false);
  });

  it('flags structured app_not_running / connection_disabled codes', () => {
    expect(isBridgeDown({ ok: false, code: 'app_not_running', error: 'open Triwarden' })).toBe(true);
    expect(isBridgeDown({ ok: false, code: 'connection_disabled', error: 'Settings' })).toBe(true);
  });

  it('falls back to known error strings when code is absent', () => {
    expect(
      isBridgeDown({
        ok: false,
        error: "Triwarden isn't running — open Triwarden to use the browser extension.",
      }),
    ).toBe(true);
    expect(
      isBridgeDown({
        ok: false,
        error: 'This connection is turned off in Settings › Browser or Developer.',
      }),
    ).toBe(true);
  });
});

describe('bridgeDownMessage', () => {
  it('prefers the reply error, then a code-specific default', () => {
    expect(bridgeDownMessage({ error: 'Custom', code: 'app_not_running' })).toBe('Custom');
    expect(bridgeDownMessage({ code: 'connection_disabled' })).toMatch(/Settings/);
    expect(bridgeDownMessage({})).toMatch(/open Triwarden/);
  });
});
