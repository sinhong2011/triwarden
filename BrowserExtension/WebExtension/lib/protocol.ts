/** What the Triwarden app answers (see CLIBridge.swift); the extension never decides anything itself. */
/**
 * `totpPeriod` is set when the login has a one-time code: its period in seconds, enough to draw a countdown.
 * `icon` is the site's icon as base64 PNG, when the app has it. `code` is the current one-time code, only when asked
 * for (`codes` on the request, sent by code fields).
 */
export type Row = {
  id: string;
  name: string;
  detail?: string;
  totpPeriod?: number;
  icon?: string;
  code?: string;
  /** The login's address is exactly this site (sorted first by the app). */
  exact?: boolean;
  /** The login also holds a passkey. The extension still fills its password: passkey sign-in is the app's. */
  passkey?: boolean;
};

export type Reply = {
  ok: boolean;
  error?: string;
  rows?: Row[];
  /** `match`: the Browser setting "Show suggestions when a field is focused". */
  autoShow?: boolean;
  username?: string;
  password?: string;
  /** `fill` only: the current one-time code, how many seconds it has left, and its period. */
  totp?: string;
  totpRemaining?: number;
  totpPeriod?: number;
};

export type Command = 'match' | 'fill' | 'save' | 'copy';
export const COMMANDS: ReadonlySet<string> = new Set<Command>(['match', 'fill', 'save', 'copy']);

export type Request = {
  command: Command;
  query?: string;
  username?: string;
  password?: string;
  field?: string;
  codes?: boolean;
  /** With `codes`: the person asked to see them. A field that only took focus never sets this. */
  reveal?: boolean;
};
