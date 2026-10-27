/** What the Triwarden app answers (see CLIBridge.swift); the extension never decides anything itself. */
export type Row = { id: string; name: string; detail?: string };

export type Reply = {
  ok: boolean;
  error?: string;
  rows?: Row[];
  username?: string;
  password?: string;
};

export type Command = 'match' | 'fill' | 'save';
export const COMMANDS: ReadonlySet<string> = new Set<Command>(['match', 'fill', 'save']);

export type Request = {
  command: Command;
  query?: string;
  username?: string;
  password?: string;
};
