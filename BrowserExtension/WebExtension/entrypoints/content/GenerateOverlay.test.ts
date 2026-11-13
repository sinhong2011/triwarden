// @vitest-environment jsdom
import { createComponent, render } from 'solid-js/web';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('../../lib/send', () => ({
  send: vi.fn(async (req: { field?: string; length?: number; uppercase?: boolean }) => {
    if (req.field === 'email') return { ok: true, value: 'me+k3x9q2ab@example.com', rows: [{ id: 'a', name: 'me@example.com' }] };
    if (req.field === 'passphrase') {
      return {
        ok: true,
        value: 'correct-horse-battery',
        length: req.length ?? 6,
        separator: '-',
        capitalize: false,
        includeNumber: false,
        entropyBits: 77,
      };
    }
    return {
      ok: true,
      value: 'Gen3rated!Pw',
      length: req.length ?? 20,
      uppercase: req.uppercase ?? true,
      lowercase: true,
      digits: true,
      symbols: true,
      avoidAmbiguous: true,
      minNumbers: 1,
      minSpecial: 1,
      entropyBits: 118,
    };
  }),
}));
const { default: GenerateOverlay } = await import('./GenerateOverlay');

HTMLElement.prototype.getBoundingClientRect = function () {
  return new DOMRect(0, 200, 300, 40);
};
const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms));
let dispose: (() => void) | undefined;
const SIGN_UP = `<form><input type=email name=e>
  <input type=password name=p autocomplete=new-password><input type=password name=c autocomplete=new-password>
  <button type=submit>Sign up</button></form>`;
const mount = async (html = SIGN_UP) => {
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1000 });
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: 800 });
  document.body.innerHTML = html;
  const host = document.createElement('div');
  document.body.append(host);
  dispose = render(() => createComponent(GenerateOverlay, {}), host);
  await tick();
  return host;
};
afterEach(() => {
  dispose?.();
  document.body.innerHTML = '';
  vi.clearAllMocks();
});

describe('GenerateOverlay sign-up helpers', () => {
  it('offers your emails and a private address; one click fills the email and a strong password, then offers to save', async () => {
    const host = await mount();
    const [, emailKey] = host.querySelectorAll<HTMLButtonElement>('.key');
    emailKey!.click();
    await tick(5);
    const rows = [...host.querySelectorAll<HTMLElement>('.row')];
    expect(rows.map((r) => r.querySelector('.name')!.textContent)).toEqual(['me@example.com', 'me+k3x9q2ab@example.com']);
    expect(host.querySelector('.hint')!.textContent).toBe('Also fills a strong password');
    // One click, like 1Password: the email, a strong password in the empty password field, and the save offer.
    rows[0]!.click();
    await tick(5);
    expect(document.querySelector<HTMLInputElement>('[name=e]')!.value).toBe('me@example.com');
    expect(document.querySelector<HTMLInputElement>('[name=p]')!.value).toBe('Gen3rated!Pw');
    expect(document.querySelector<HTMLInputElement>('[name=c]')!.value).toBe('Gen3rated!Pw');
    const { send } = await import('../../lib/send');
    expect(send).toHaveBeenCalledWith({ command: 'save', username: 'me@example.com', password: 'Gen3rated!Pw' });
  });

  it('↓ and Enter in the email field pick a row, as in the vault fill menu', async () => {
    const host = await mount();
    host.querySelectorAll<HTMLButtonElement>('.key')[1]!.click();
    await tick(5);
    const field = document.querySelector<HTMLInputElement>('[name=e]')!;
    const key = (k: string) => field.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }));
    key('ArrowDown');
    key('ArrowDown');
    key('Enter');
    expect(field.value).toBe('me+k3x9q2ab@example.com');
  });
});

describe('GenerateOverlay', () => {
  it('shows a suggested password as soon as the menu opens, and one click fills both fields', async () => {
    const host = await mount();
    const keys = host.querySelectorAll<HTMLButtonElement>('.key');
    expect(keys).toHaveLength(2); // the new password, and the sign-up's email field
    // The field rect is 0–300; the icon sits just to its right, not over the value.
    expect(keys[0]!.style.left).toBe('300px');
    keys[0]!.click();
    await tick(5);
    expect(host.querySelector('.gen-value')!.textContent).toBe('Gen3rated!Pw');
    expect(document.querySelector<HTMLInputElement>('[name=p]')!.value).toBe(''); // shown, not filled yet
    host.querySelector<HTMLElement>('.gen-row')!.click();
    expect(document.querySelector<HTMLInputElement>('[name=p]')!.value).toBe('Gen3rated!Pw');
    expect(document.querySelector<HTMLInputElement>('[name=c]')!.value).toBe('Gen3rated!Pw');
    expect(host.querySelector('.menu')).toBeNull();
    // No username yet: the submit offers to save instead (no nameless login waiting in the app).
    const { send } = await import('../../lib/send');
    expect(send).not.toHaveBeenCalledWith(expect.objectContaining({ command: 'save' }));
  });

  it('Return in the field uses the suggestion instead of submitting', async () => {
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    const field = document.querySelector<HTMLInputElement>('[name=p]')!;
    const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true });
    field.dispatchEvent(enter);
    expect(enter.defaultPrevented).toBe(true);
    expect(field.value).toBe('Gen3rated!Pw');
  });

  it('switching to passphrase asks for one', async () => {
    const { send } = await import('../../lib/send');
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    expect(host.querySelector('.gen-kinds')!.getAttribute('data-kind')).toBe('password');
    expect(host.querySelector('.gen-kinds-thumb')).not.toBeNull();
    // Prior suggestion stays visible during soft tab switch (no Generating flash).
    const before = host.querySelector('.gen-value')!.textContent;
    host.querySelectorAll<HTMLButtonElement>('.gen-kinds button')[1]!.click();
    expect(host.querySelector('.gen-kinds')!.getAttribute('data-kind')).toBe('passphrase');
    expect(host.querySelector('.gen-value')!.textContent).toBe(before);
    await tick(5);
    expect(vi.mocked(send).mock.calls.at(-1)![0]).toEqual({ command: 'generate', field: 'passphrase' });
    expect(host.querySelector('.gen-value')!.textContent).toBe('correct-horse-battery');
    expect(host.querySelector('.gen-tab-pane')!.getAttribute('data-kind')).toBe('passphrase');
  });

  it('shows Length / Include chips / strength / Use Password like the app compact generator', async () => {
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    expect(host.querySelector('.gen-slider')).not.toBeNull();
    expect(host.querySelectorAll('.gen-chip').length).toBe(4);
    const { t } = await import('../../lib/i18n');
    expect(host.querySelector('.gen-strength-label')!.textContent).toBe(t('gen.veryStrong'));
    expect(host.querySelector('.gen-toggle[role="switch"]')).not.toBeNull();
    expect(host.querySelector('.gen-mins')).not.toBeNull();
    expect(host.querySelector('.gen-use')!.textContent).toBe(t('gen.usePassword'));
    // No native title tooltip that truncates over the controls.
    expect(host.querySelector('.gen-row')!.getAttribute('title')).toBeNull();
    host.querySelector<HTMLButtonElement>('.gen-use')!.click();
    expect(document.querySelector<HTMLInputElement>('[name=p]')!.value).toBe('Gen3rated!Pw');
  });

  it('changing Length re-generates with the new length so the app can persist prefs', async () => {
    const { send } = await import('../../lib/send');
    const { t } = await import('../../lib/i18n');
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    // First call loads saved prefs (no overrides); reply seeds local state.
    expect(vi.mocked(send).mock.calls[0]![0]).toEqual({ command: 'generate', field: undefined });
    const before = vi.mocked(send).mock.calls.length;
    const plus = host.querySelector<HTMLButtonElement>(`.gen-stepper button[aria-label="${t('gen.increase', t('gen.length'))}"]`)!;
    plus.click();
    plus.click(); // coalesce: two quick steps → one debounced generate
    await tick(5);
    expect(vi.mocked(send).mock.calls.length).toBe(before); // still within debounce window
    await tick(200);
    const last = vi.mocked(send).mock.calls.at(-1)![0] as Record<string, unknown>;
    expect(last.command).toBe('generate');
    expect(last.length).toBe(22);
    expect(last.uppercase).toBe(true);
    expect(last.digits).toBe(true);
  });

  it('keeps the previous suggestion visible while options regenerate (no Generating flash)', async () => {
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    expect(host.querySelector('.gen-value')!.textContent).toBe('Gen3rated!Pw');
    host.querySelectorAll<HTMLButtonElement>('.gen-chip')[0]!.click();
    await tick(5); // still debouncing / soft — value must not blank
    expect(host.querySelector('.gen-value')!.textContent).toBe('Gen3rated!Pw');
    expect(host.querySelector('.gen-value')!.getAttribute('data-loading')).not.toBe('true');
  });

  it('keeps X and Y after drag ends (absolute place, not a cleared delta)', async () => {
    const host = await mount();
    host.querySelector<HTMLButtonElement>('.key')!.click();
    await tick(5);
    const card = host.querySelector<HTMLElement>('.menu.gen')!;
    const handle = host.querySelector<HTMLElement>('.gen-drag')!;
    // Seed a known place so the test does not depend on jsdom layout.
    card.style.left = '40px';
    card.style.top = '80px';
    // Solid owns style on re-render; dispatch drag which writes left/top via menuPos + direct DOM.
    handle.dispatchEvent(
      new PointerEvent('pointerdown', {
        button: 0,
        clientX: 100,
        clientY: 100,
        pointerId: 1,
        bubbles: true,
        cancelable: true,
      }),
    );
    document.dispatchEvent(
      new PointerEvent('pointermove', {
        clientX: 180,
        clientY: 30,
        pointerId: 1,
        bubbles: true,
        cancelable: true,
      }),
    );
    document.dispatchEvent(
      new PointerEvent('pointerup', {
        clientX: 180,
        clientY: 30,
        pointerId: 1,
        bubbles: true,
        cancelable: true,
      }),
    );
    await tick(0);

    const left = Number.parseFloat(card.style.left);
    const top = Number.parseFloat(card.style.top);
    expect(left).toBeGreaterThan(40); // moved +X
    expect(top).toBeLessThan(80); // moved -Y
    // Release must keep the place (no snap-back to the pre-drag spot).
    expect(left).not.toBe(40);
  });
});
