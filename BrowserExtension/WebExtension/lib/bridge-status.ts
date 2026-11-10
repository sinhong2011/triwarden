import { t } from './i18n';
import type { Reply } from './protocol';

/** Codes the native bridge returns when Triwarden is unreachable (see BridgeClient.unavailableResponse). */
export const BRIDGE_DOWN_CODES = new Set(['app_not_running', 'connection_disabled']);

/** True when a reply means the extension cannot reach a live bridge (not “no logins for this site”). */
export function isBridgeDown(reply: Pick<Reply, 'ok' | 'code' | 'error'> | null | undefined): boolean {
  if (!reply || reply.ok) return false;
  if (reply.code && BRIDGE_DOWN_CODES.has(reply.code)) return true;
  // Older builds without `code`: keep the actionable English strings from BridgeClient.
  const msg = reply.error ?? '';
  return /isn't running/i.test(msg) || /turned off in Settings/i.test(msg);
}

/**
 * Message for the Safari bridge-down banner (and any UI that needs a localized unreachable note).
 *
 * **Approach (issue #207):** known bridge-down `code` values are translated here from the browser UI
 * language. The app still sends an English `error` string for logs and older hosts; the extension
 * does not display that copy when a code is present. Other failures (denied, no matches, …) keep
 * using the app's `error` text, which is already localized to the app locale.
 */
export function bridgeDownMessage(reply: Pick<Reply, 'error' | 'code'> | null | undefined): string {
  if (reply?.code === 'connection_disabled') return t('bridge.connectionDisabled');
  if (reply?.code === 'app_not_running') return t('bridge.appNotRunning');
  // Legacy hosts without `code`: keep whatever English string the bridge returned.
  if (reply?.error) return reply.error;
  return t('bridge.appNotRunning');
}

/** Prefer a code-translated bridge-down note; otherwise the reply error or a localized fallback. */
export function replyErrorMessage(
  reply: Pick<Reply, 'error' | 'code'> | null | undefined,
  fallbackKey = 'unavailable',
): string {
  if (reply?.code && BRIDGE_DOWN_CODES.has(reply.code)) return bridgeDownMessage(reply);
  return reply?.error || t(fallbackKey);
}
