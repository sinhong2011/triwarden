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
  /** `pending`: the account Save writes to, named only when more than one is unlocked. */
  account?: string;
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
  /** Machine-readable failure: `app_not_running`, `connection_disabled`, `vault_locked`, … */
  code?: string;
  rows?: Row[];
  /** `match`: the Browser setting "Show suggestions when a field is focused". */
  autoShow?: boolean;
  /** `pending`: the unlocked accounts a new login can go to (`id`, `name` = email), only when there is more than one. */
  accounts?: Row[];
  username?: string;
  password?: string;
  /** `fill` only: the current one-time code, how many seconds it has left, and its period. */
  totp?: string;
  totpRemaining?: number;
  totpPeriod?: number;
  /** `fill`: the app also put the one-time code on the clipboard (same approval as the fill). */
  totpCopied?: boolean;
  /** `generate`: the fresh password or passphrase. */
  value?: string;
} & GeneratorOptions;

/** `pending`: logins waiting to be saved for this site (rows: `name` = login it updates, `detail` = username); with
 *  `query` (a row id) answers it, `field: 'save'` saves, anything else is Not Now. */
export type Command = 'match' | 'fill' | 'save' | 'copy' | 'generate' | 'pending';
export const COMMANDS: ReadonlySet<string> = new Set<Command>(['match', 'fill', 'save', 'copy', 'generate', 'pending']);

export type Request = {
  command: Command;
  query?: string;
  /** `pending` Save: the unlocked account (an `accounts` id) to save a new login to. */
  account?: string;
  username?: string;
  password?: string;
  /** `get` / `copy` / `generate`: for generate, `passphrase` asks for a passphrase instead of a password. */
  field?: string;
  codes?: boolean;
  /** The person asked (icon or shortcut). With `codes`, also return the digits. A field that only took focus never sets this. */
  reveal?: boolean;
  /**
   * `match`: the person asked to fill (icon or shortcut). The app brings its window forward when the
   * vault is locked. Omit on background match (right-click menu rebuild).
   */
  foreground?: boolean;
  /** `match`: rebuilding the right-click menu — do not open unlock while locked. */
  silent?: boolean;
  /**
   * `fill`: `false` when this page has a one-time-code field (the code goes in the form). `true` asks
   * the app to copy the code with this fill's approval when the Browser setting is on. Omit it and
   * the app still copies if the setting is on (older content scripts). The value never goes through
   * the extension's clipboard.
   */
  copyTotp?: boolean;
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
