import type { Reply } from './protocol';

/** Codes the native bridge returns when Triwarden is unreachable (see BridgeClient.unavailableResponse). */
export const BRIDGE_DOWN_CODES = new Set(['app_not_running', 'connection_disabled']);

/** True when a reply means the extension cannot reach a live bridge (not “no logins for this site”). */
export function isBridgeDown(reply: Pick<Reply, 'ok' | 'code' | 'error'> | null | undefined): boolean {
  if (!reply || reply.ok) return false;
  if (reply.code && BRIDGE_DOWN_CODES.has(reply.code)) return true;
  // Older builds without `code`: keep the actionable strings from BridgeClient.
  const msg = reply.error ?? '';
  return /isn't running/i.test(msg) || /turned off in Settings/i.test(msg);
}

/** Message to show on ordinary Safari login pages (system AutoFill owns fill; this is the only surface). */
export function bridgeDownMessage(reply: Pick<Reply, 'error' | 'code'> | null | undefined): string {
  if (reply?.error) return reply.error;
  if (reply?.code === 'connection_disabled') {
    return 'This connection is turned off in Settings › Browser or Developer.';
  }
  return "Triwarden isn't running — open Triwarden to use the browser extension.";
}
