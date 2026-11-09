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

/** Options echoed by `generate` (and accepted on the request) — same keys as the app Generator prefs. */
export type GeneratorOptions = {
  /** Password character count, or passphrase word count. */
  length?: number;
  uppercase?: boolean;
  lowercase?: boolean;
  digits?: boolean;
  symbols?: boolean;
  avoidAmbiguous?: boolean;
  minNumbers?: number;
  minSpecial?: number;
  separator?: string;
  capitalize?: boolean;
  includeNumber?: boolean;
  /** Entropy estimate in bits for the strength meter. */
  entropyBits?: number;
};

export type Reply = {
  ok: boolean;
  error?: string;
  /** Machine-readable failure: `app_not_running`, `connection_disabled`, … */
  code?: string;
  rows?: Row[];
  /** `match`: the Browser setting "Show suggestions when a field is focused". */
  autoShow?: boolean;
  username?: string;
  password?: string;
  /** `fill` only: the current one-time code, how many seconds it has left, and its period. */
  totp?: string;
  totpRemaining?: number;
  totpPeriod?: number;
  /** `generate`: the fresh password or passphrase. */
  value?: string;
} & GeneratorOptions;

export type Command = 'match' | 'fill' | 'save' | 'copy' | 'generate';
export const COMMANDS: ReadonlySet<string> = new Set<Command>(['match', 'fill', 'save', 'copy', 'generate']);

export type Request = {
  command: Command;
  query?: string;
  username?: string;
  password?: string;
  /** `get` / `copy` / `generate`: for generate, `passphrase` asks for a passphrase instead of a password. */
  field?: string;
  codes?: boolean;
  /** With `codes`: the person asked to see them. A field that only took focus never sets this. */
  reveal?: boolean;
  /** `generate` password: optional length override (passphrase: word count). */
  length?: number;
  /** `generate` password charset / rules — persisted into the app's `generator` prefs when sent. */
  uppercase?: boolean;
  lowercase?: boolean;
  digits?: boolean;
  symbols?: boolean;
  avoidAmbiguous?: boolean;
  minNumbers?: number;
  minSpecial?: number;
  /** `generate` passphrase options — persisted into `passphraseGenerator` when sent. */
  separator?: string;
  capitalize?: boolean;
  includeNumber?: boolean;
};
