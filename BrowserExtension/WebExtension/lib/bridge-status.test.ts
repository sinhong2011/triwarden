import { describe, expect, it } from 'vitest';
import { bridgeDownMessage, isBridgeDown, replyErrorMessage } from './bridge-status';
import { t } from './i18n';

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
  it('translates known codes (not the English reply.error)', () => {
    expect(bridgeDownMessage({ error: 'Custom', code: 'app_not_running' })).toBe(t('bridge.appNotRunning'));
    expect(bridgeDownMessage({ error: 'Custom', code: 'connection_disabled' })).toBe(t('bridge.connectionDisabled'));
    expect(bridgeDownMessage({})).toBe(t('bridge.appNotRunning'));
  });

  it('keeps legacy English error text when code is absent', () => {
    expect(bridgeDownMessage({ error: 'Legacy host message' })).toBe('Legacy host message');
  });
});

describe('replyErrorMessage', () => {
  it('maps bridge-down codes to localized copy and keeps other errors', () => {
    expect(replyErrorMessage({ code: 'connection_disabled', error: 'Settings' })).toBe(t('bridge.connectionDisabled'));
    expect(replyErrorMessage({ error: 'Denied' })).toBe('Denied');
    expect(replyErrorMessage({})).toBe(t('unavailable'));
  });
});
