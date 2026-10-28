// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// `send` talks to the extension runtime; the tests only care what would be sent.
const sent: Array<Record<string, unknown>> = [];
vi.mock('./send', () => ({
  send: vi.fn(async (request: Record<string, unknown>) => {
    sent.push(request);
    return { ok: true };
  }),
}));

const { watchForSubmits } = await import('./save');

// jsdom has no layout, so every box measures 0 x 0 and the real `visible()` (which picks the username field) would call
// every field hidden. Give them a size instead of replacing `visible()`, which `usernameFor` uses from inside dom.ts.
HTMLElement.prototype.getBoundingClientRect = () => new DOMRect(0, 0, 200, 40);

let installed = false;
const mount = (html: string) => {
  document.body.innerHTML = html;
  if (!installed) {
    watchForSubmits(); // the listeners live on the document and survive across tests
    installed = true;
  }
};
const saves = () => sent.filter((r) => r.command === 'save');
const click = (el: Element) => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
const press = (el: Element, key: string) => el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
const fill = (el: Element | null, value: string) => ((el as HTMLInputElement).value = value);

// A password is only offered once per username and password pair, so each test uses its own.
let n = 0;
const creds = () => ({ user: ` user${++n}@example.com `, pw: `pw-${n}-secret` });

beforeEach(() => {
  sent.length = 0;
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('offering to save a login', () => {
  it('offers on a form submit, with the username trimmed', () => {
    const { user, pw } = creds();
    // type=text: a browser already strips the spaces around an email field's value, so only text keeps them.
    mount('<form id=f><input name=u type=text><input name=p type=password><button type=submit>Go</button></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    document.getElementById('f')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(saves()).toEqual([{ command: 'save', username: user.trim(), password: pw }]);
  });

  it('offers when the form’s submit button is clicked', () => {
    const { user, pw } = creds();
    mount('<form><input name=u type=email><input name=p type=password><button type=submit id=go>Go</button></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('go')!);
    expect(saves()).toHaveLength(1);
  });

  it('ignores a type="button" control inside a form, such as show password', () => {
    const { user, pw } = creds();
    mount('<form><input name=u type=email><input name=p type=password><button type=button id=eye>Show</button></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('eye')!);
    expect(saves()).toHaveLength(0);
  });

  it('ignores a click on a [role=button] inside a form: the form’s own submit covers it', () => {
    const { user, pw } = creds();
    mount('<form><input name=u type=email><input name=p type=password><div role=button id=fake>Sign in</div></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('fake')!);
    expect(saves()).toHaveLength(0);
  });

  it('ignores a disabled button', () => {
    const { user, pw } = creds();
    mount('<form><input name=u type=email><input name=p type=password><button type=submit id=go disabled>Go</button></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('go')!);
    expect(saves()).toHaveLength(0);
  });

  it('offers nothing when no password was typed', () => {
    mount('<form id=f><input name=u type=email><input name=p type=password><button type=submit>Go</button></form>');
    fill(document.querySelector('[name=u]'), creds().user);
    document.getElementById('f')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(saves()).toHaveLength(0);
  });

  it('does not offer the same login twice in a row', () => {
    const { user, pw } = creds();
    mount('<form id=f><input name=u type=email><input name=p type=password></form>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    const form = document.getElementById('f')!;
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(saves()).toHaveLength(1);
  });

  it('on a change-password form saves the new password, not the old one', () => {
    const { user, pw } = creds();
    // The new password comes first: "the last one filled" would pick the old one, so only a preference for
    // new-password gives the right answer.
    mount(
      '<form id=f><input name=u type=email><input name=new type=password autocomplete=new-password>' +
        '<input name=old type=password autocomplete=current-password></form>',
    );
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=old]'), 'old-password-value');
    fill(document.querySelector('[name=new]'), pw);
    document.getElementById('f')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(saves().map((r) => r.password)).toEqual([pw]);
  });
});

describe('pages with no form', () => {
  const page = '<input name=u type=email><input name=p type=password>';

  it('offers when a button that reads like logging in is clicked', () => {
    const { user, pw } = creds();
    mount(page + '<button id=go>Sign in</button>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('go')!);
    expect(saves()).toHaveLength(1);
  });

  it('ignores a button that does not read like logging in', () => {
    const { user, pw } = creds();
    mount(page + '<button id=menu>Open menu</button>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('menu')!);
    expect(saves()).toHaveLength(0);
  });

  it('reads an aria-label too', () => {
    const { user, pw } = creds();
    mount(page + '<div role=button id=go aria-label="Log in"></div>');
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    click(document.getElementById('go')!);
    expect(saves()).toHaveLength(1);
  });

  it('offers on Enter in the password field', () => {
    const { user, pw } = creds();
    mount(page);
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    press(document.querySelector('[name=p]')!, 'Enter');
    expect(saves()).toHaveLength(1);
  });

  it('ignores other keys', () => {
    const { user, pw } = creds();
    mount(page);
    fill(document.querySelector('[name=u]'), user);
    fill(document.querySelector('[name=p]'), pw);
    press(document.querySelector('[name=p]')!, 'a');
    expect(saves()).toHaveLength(0);
  });
});
