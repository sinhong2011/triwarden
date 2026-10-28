/** What the Triwarden app answers (see CLIBridge.swift); the extension never decides anything itself. */
/** `totpPeriod` is set when the login has a one-time code: its period in seconds, enough to draw a countdown. */
export type Row = { id: string; name: string; detail?: string; totpPeriod?: number };

export type Reply = {
  ok: boolean;
  error?: string;
  rows?: Row[];
  username?: string;
  password?: string;
  /** `fill` only: the current one-time code, how many seconds it has left, and its period. */
  totp?: string;
  totpRemaining?: number;
  totpPeriod?: number;
};

export type Command = 'match' | 'fill' | 'save';
export const COMMANDS: ReadonlySet<string> = new Set<Command>(['match', 'fill', 'save']);

export type Request = {
  command: Command;
  query?: string;
  username?: string;
  password?: string;
};
