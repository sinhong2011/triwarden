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
