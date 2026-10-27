// Offer to save what you typed when a login form is submitted. Passwords are never stored by the extension.
//
// Only a real login attempt counts: a form's submit, a click on its submit button (some pages handle that click
// themselves and never fire submit), or, on pages with no form, Enter in the password field or a button that
// reads like logging in. Other clicks (show password, menus, anything outside the form) never offer to save.
// The app doesn't interrupt: it posts a notification and keeps the login in its bell until you answer.
import { send } from './send';
import { textLike, usernameFor } from './dom';

const LOGIN_LABEL =
  /\b(log ?in|log ?on|sign ?in|sign ?on|sign ?up|register|create account|continue|next|submit|save|update|change password)\b/i;

let lastOffer = '';

/** The password worth saving in `scope`: the new one on a change-password form, else the last one filled. */
function submittedPassword(scope: ParentNode): HTMLInputElement | undefined {
  const filled = [...scope.querySelectorAll<HTMLInputElement>('input[type="password"]')].filter((p) => p.value);
  return filled.find((p) => /new-password/.test(p.autocomplete || '')) || filled[filled.length - 1];
}

function offerSave(scope: ParentNode): void {
  const pw = submittedPassword(scope);
  if (!pw) return;
  const username = (usernameFor(pw)?.value || '').trim();
  const key = `${username}\u0000${pw.value}`;
  if (key === lastOffer) return;
  lastOffer = key;
  void send({ command: 'save', username, password: pw.value });
}

export function watchForSubmits(): void {
  document.addEventListener('submit', (e) => offerSave(e.target as HTMLFormElement), true);

  document.addEventListener(
    'click',
    (e) => {
      const b = (e.target as Element | null)?.closest?.<HTMLButtonElement>(
        'button, input[type="submit"], input[type="button"], [role="button"]',
      );
      if (!b || b.disabled) return;
      if (b.form) {
        // Inside a form only its submit button counts; type="button" ones (show password, etc.) never do.
        if (b.type === 'submit') offerSave(b.form);
        return;
      }
      if (b.closest('form')) return; // a [role=button] inside a form: the form's own submit covers it
      const label = `${b.textContent || ''} ${b.value || ''} ${b.getAttribute('aria-label') || ''}`;
      if (LOGIN_LABEL.test(label)) offerSave(document);
    },
    true,
  );

  document.addEventListener(
    'keydown',
    (e) => {
      const t = e.target;
      if (e.key === 'Enter' && t instanceof HTMLInputElement && !t.form && (t.type === 'password' || textLike(t))) {
        offerSave(document);
      }
    },
    true,
  );
}
