/** Page inspection shared by the overlay and the save offer. Pure DOM, no extension APIs. */

export const visible = (el: HTMLElement): boolean => {
  const r = el.getBoundingClientRect();
  const s = getComputedStyle(el);
  return (
    r.width > 20 && r.height > 10 && s.visibility !== 'hidden' && s.display !== 'none' && !(el as HTMLInputElement).disabled
  );
};

export const textLike = (input: HTMLInputElement): boolean => {
  const type = (input.getAttribute('type') || 'text').toLowerCase();
  return ['text', 'email', 'tel', ''].includes(type) || /username|email/.test(input.autocomplete || '');
};

/** The username field that belongs to a password field: the nearest text-like input before it. */
export function usernameFor(pw: HTMLInputElement): HTMLInputElement | null {
  const scope: ParentNode = pw.form || document;
  const inputs = [...scope.querySelectorAll('input')].filter(visible);
  const at = inputs.indexOf(pw);
  for (const input of inputs.slice(0, Math.max(at, 0)).reverse()) if (textLike(input)) return input;
  return scope.querySelector('input[autocomplete~="username"], input[type="email"]');
}

/** Whether a field lays out right to left (Persian, Arabic, Hebrew pages): its text starts at the right edge. */
export const isRTL = (el: Element): boolean => getComputedStyle(el).direction === 'rtl';

/** Set a value the way a user would, so frameworks that track input events notice it. */
export function setValue(input: HTMLInputElement | null | undefined, value: string | undefined): void {
  if (!input || value == null) return;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  input.focus();
  setter.call(input, value);
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
}

export const passwordFields = (): HTMLInputElement[] =>
  [...document.querySelectorAll<HTMLInputElement>('input[type="password"]')];

const OTP_HINT = /one-?time|otp|totp|2fa|mfa|verification|security.?code|auth(?:enticator)?.?code/i;

/**
 * Where a one-time code goes. Each entry is one code: a single field, or the row of one-digit boxes some sites use
 * (all of them, in order). Only fields that say what they are count: `autocomplete="one-time-code"`, or a name,
 * id or label that reads like a verification code and is not a password.
 */
export function otpTargets(): HTMLInputElement[][] {
  const inputs = [...document.querySelectorAll<HTMLInputElement>('input')].filter(
    (i) => visible(i) || (i.maxLength === 1 && i.getBoundingClientRect().width > 8),
  );
  const claimed = new Set<HTMLInputElement>();
  const found: HTMLInputElement[][] = [];
  for (const input of inputs) {
    if (claimed.has(input) || input.type === 'password' || input.type === 'hidden') continue;
    const hint = [input.autocomplete, input.name, input.id, input.getAttribute('aria-label'), input.placeholder].join(' ');
    const says = /one-time-code/.test(input.autocomplete || '') || OTP_HINT.test(hint);
    if (!says) continue;
    // One-digit boxes next to each other in the same form are one code.
    const scope: ParentNode = input.form || document;
    const boxes = [...scope.querySelectorAll<HTMLInputElement>('input')].filter((i) => i.maxLength === 1 && !i.disabled);
    if (input.maxLength === 1 && boxes.length >= 4 && boxes.length <= 10 && boxes.includes(input)) {
      boxes.forEach((b) => claimed.add(b));
      found.push(boxes);
    } else {
      claimed.add(input);
      found.push([input]);
    }
  }
  return found;
}

/** Put a one-time code in a field, or spread it over one-digit boxes. */
export function fillOtp(boxes: HTMLInputElement[], code: string): void {
  if (boxes.length === 1) return setValue(boxes[0], code);
  boxes.forEach((box, i) => setValue(box, code[i]));
  boxes[Math.min(code.length, boxes.length) - 1]?.focus();
}


/**
 * The group a password field belongs to: its form, else the nearest wrapper that also holds a button (SPA sign-up
 * pages often have no <form>), else the whole page.
 */
export function fieldScope(field: HTMLElement): ParentNode {
  const form = (field as HTMLInputElement).form;
  if (form) return form;
  let el = field.parentElement;
  for (let depth = 0; el && el !== document.body && depth < 8; depth++, el = el.parentElement) {
    if (el.querySelector('button, input[type="submit"], input[type="button"], [role="button"]')) return el;
  }
  return document;
}

const fieldText = (f: HTMLInputElement): string => {
  const labels = [...(f.labels ?? [])].map((l) => l.textContent);
  return [f.name, f.id, f.getAttribute('aria-label'), f.placeholder, ...labels].filter(Boolean).join(' ');
};

const CURRENT_HINT = /\b(current|old|existing)\b|current.?pass|old.?pass/i;
const CONFIRM_HINT = /confirm|re-?enter|re-?type|repeat|again|verify|(?:pass(?:word)?|pwd)[-_ ]?2\b/i;
/** A button or heading that says the page makes or changes a password. */
const SIGNUP_HINT =
  /\b(sign\s*up|register|registration|join|get\s+started|create\s+(?:an?\s+|your\s+|new\s+)?(?:account|password)|new\s+(?:account|password)|change\s+(?:your\s+)?password|set\s+(?:a\s+|your\s+)?(?:new\s+)?password|choose\s+(?:a\s+)?password|reset\s+(?:your\s+)?password|update\s+(?:your\s+)?password)\b/i;
/** A submit control that says this is a sign-in. Decides over headings: login pages often say "Sign up" somewhere. */
const SIGNIN_HINT = /\b(log\s*in|log\s*on|sign\s*in|sign\s*on|continue\s+with\s+password|unlock)\b/i;
/** Secondary buttons that never describe the form ("Forgot password?", "Show password"). */
const ASIDE_HINT =
  /forgot|trouble|can.?t|show|hide|reveal|toggle|already|have\s+an\s+account|instead|back\s+to|with\s+(google|apple|github|microsoft|facebook|sso)|passkey/i;

const visiblePasswords = (scope: ParentNode): HTMLInputElement[] =>
  [...scope.querySelectorAll<HTMLInputElement>('input[type="password"]')].filter(visible);

/** What a group of password fields is for, decided by its submit button first and its headings second. */
function scopeIntent(scope: ParentNode): 'signup' | 'signin' | 'unknown' {
  const label = (b: Element) =>
    `${b.textContent || ''} ${(b as HTMLInputElement).value || ''} ${b.getAttribute('aria-label') || ''}`;
  const all = [...scope.querySelectorAll<HTMLElement>('button, input[type="submit"], input[type="button"], [role="button"]')]
    .filter(visible)
    .filter((b) => !ASIDE_HINT.test(label(b)));
  // The submit button speaks for the form; other buttons ("Sign up" next to "Log in") only when there is none.
  const submits = all.filter((b) => (b as HTMLButtonElement).type === 'submit');
  for (const group of [submits, all]) {
    const texts = group.map(label);
    if (texts.some((t) => SIGNIN_HINT.test(t)) && !texts.some((t) => SIGNUP_HINT.test(t))) return 'signin';
    if (texts.some((t) => SIGNUP_HINT.test(t)) && !texts.some((t) => SIGNIN_HINT.test(t))) return 'signup';
    if (group.length && texts.some((t) => SIGNIN_HINT.test(t))) return 'signin'; // mixed: never guess signup
  }
  const form = scope instanceof HTMLFormElement ? scope : null;
  const headings = [...scope.querySelectorAll('h1, h2, h3, legend')].map((h) => h.textContent);
  const page = [form?.id, form?.name, form?.getAttribute('aria-label'), form?.getAttribute('action'), ...headings];
  if (SIGNUP_HINT.test(page.filter(Boolean).join(' '))) return 'signup';
  if (scope === document && /\/(sign-?up|register|join|create-account)\b/i.test(location.pathname)) return 'signup';
  return 'unknown';
}

/** Words that say a form makes an account, not a new password for one (change, reset). */
const ACCOUNT_HINT =
  /\b(sign\s*up|register|registration|join|get\s+started|create\s+(?:an?\s+|your\s+|new\s+)?account|new\s+account)\b/i;

/** Whether the group's buttons or headings (or the page's path) say it creates an account. */
function makesAccount(scope: ParentNode): boolean {
  const texts = [...scope.querySelectorAll<HTMLElement>('button, input[type="submit"], [role="button"], h1, h2, h3, legend')]
    .map((e) => `${e.textContent || ''} ${(e as HTMLInputElement).value || ''}`);
  return (
    ACCOUNT_HINT.test(texts.join(' ')) ||
    (scope === document && /\/(sign-?up|register|join|create-account)\b/i.test(location.pathname))
  );
}

/**
 * A password field to generate for, the field that confirms it (filled with the same value), and on a sign-up the
 * username or email field next to it (offered your emails or a new username).
 */
export type GenerateTarget = { field: HTMLInputElement; confirm?: HTMLInputElement; username?: HTMLInputElement };

const EMAIL_HINT = /e-?mail/i;
/** Whether a username field wants an email address. */
export const wantsEmail = (input: HTMLInputElement): boolean =>
  input.type === 'email' || EMAIL_HINT.test(`${input.autocomplete} ${fieldText(input)}`);

/**
 * Where the Triwarden generate icon goes: the new password of a sign-up, change-password or reset form, never
 * an ordinary login (vault fill owns those), never the old password, never the confirm field (it gets
 * the same value). Save/Update still runs via `watchForSubmits`, with no icon at all.
 */
export function generateTargetFor(scope: ParentNode): GenerateTarget | null {
  const passwords = visiblePasswords(scope);
  if (!passwords.length) return null;
  const isCurrent = (p: HTMLInputElement) =>
    /current-password/.test(p.autocomplete || '') || (!/new-password/.test(p.autocomplete || '') && CURRENT_HINT.test(fieldText(p)));
  const fresh = passwords.filter((p) => !isCurrent(p));
  if (!fresh.length) return null;
  const marked = fresh.filter((p) => /new-password/.test(p.autocomplete || ''));
  // Anything after the new one that says "confirm", or simply the next fresh field.
  // A sign-up also gets its username field, when it sits in the same group. Not a change or reset form: a text field
  // there is rarely the account's name.
  const user = passwords.length === fresh.length && makesAccount(scope) ? usernameFor(fresh[0]!) : null;
  const username =
    user && visible(user) && !user.readOnly && (scope === document || scope.contains(user)) ? user : undefined;
  const pick = (field: HTMLInputElement): GenerateTarget => {
    const rest = fresh.slice(fresh.indexOf(field) + 1);
    return { field, confirm: rest.find((p) => CONFIRM_HINT.test(fieldText(p))) ?? rest[0], username };
  };
  const first = fresh.find((p) => !CONFIRM_HINT.test(fieldText(p))) ?? fresh[0]!;
  if (marked.length) return pick(marked.find((p) => !CONFIRM_HINT.test(fieldText(p))) ?? marked[0]!);
  // Two or more fields (new + confirm, or old + new + confirm) only happen when a password is being made.
  if (passwords.length >= 2) return pick(first);
  if (/current-password/.test(passwords[0]!.autocomplete || '')) return null;
  return scopeIntent(scope) === 'signup' ? pick(first) : null;
}

/** Whether `pw` is the field the generate icon belongs on. */
export function isGeneratePasswordField(pw: HTMLInputElement): boolean {
  if (pw.type !== 'password' || !visible(pw)) return false;
  return generateTargetFor(fieldScope(pw))?.field === pw;
}

/** Every place on the page to offer generate: one per form or group. */
export function generateTargets(): GenerateTarget[] {
  const scopes = new Set(passwordFields().filter(visible).map(fieldScope));
  return [...scopes].map(generateTargetFor).filter((t): t is GenerateTarget => !!t);
}

/** Visible password fields that warrant a generate affordance. */
export function generatePasswordFields(): HTMLInputElement[] {
  return generateTargets().map((t) => t.field);
}
