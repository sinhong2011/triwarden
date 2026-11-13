// @vitest-environment jsdom
import { createComponent, render } from 'solid-js/web';
import { expect, it, vi } from 'vitest';

// The background says a login waits in this tab, typed on example.com (an iframe or the page before a redirect).
vi.mock('wxt/browser', () => ({
  browser: {
    runtime: {
      sendMessage: vi.fn(async () => 'https://accounts.example.com/signup'),
      onMessage: { addListener: vi.fn(), removeListener: vi.fn() },
    },
  },
}));
let waiting = [{ id: 'p1', name: '', detail: 'me@example.com', account: 'work@vault.example' }];
let failNext = true;
let accounts: { id: string; name: string; detail: string }[] | undefined;
vi.mock('../../lib/send', () => ({
  send: vi.fn(async (req: { query?: string }) => {
    if (!req.query) return { ok: true, rows: waiting, accounts };
    if (failNext) {
      failNext = false;
      return { ok: false, error: "Couldn't save it. It's still waiting in Triwarden." };
    }
    waiting = waiting.filter((r) => r.id !== req.query);
    return { ok: true, value: 'done' };
  }),
}));
const { default: SavePrompt } = await import('./SavePrompt');
const { send } = await import('../../lib/send');
const tick = () => new Promise((r) => setTimeout(r, 0));

it('shows the waiting login for the site it was typed on; a failed save keeps the choices, a retry saves', async () => {
  const host = document.createElement('div');
  document.body.append(host);
  const dispose = render(() => createComponent(SavePrompt, {}), host);
  await tick();
  expect(host.querySelector('.save-title')!.textContent).toBe('Save this login for accounts.example.com?');
  expect(host.querySelector('.save-detail')!.textContent).toBe('me@example.com');
  // More than one unlocked account: the card names the one Save writes to.
  const { t } = await import('../../lib/i18n');
  expect(host.querySelectorAll('.save-detail')[1]!.textContent).toBe(t('save.toAccount', 'work@vault.example'));

  host.querySelector<HTMLButtonElement>('.save-go')!.click();
  await tick();
  expect(host.querySelector('.save-error')!.textContent).toBe("Couldn't save it. It's still waiting in Triwarden.");
  expect(host.querySelector('.save-go')).not.toBeNull(); // still there to try again

  host.querySelector<HTMLButtonElement>('.save-go')!.click();
  await tick();
  expect(send).toHaveBeenLastCalledWith({ command: 'pending', query: 'p1', field: 'save' });
  expect(host.querySelector('.save-title')!.textContent).toBe('Saved to work@vault.example.');
  expect(host.querySelector('.save-actions')).toBeNull();
  dispose();
});

it('with more than one unlocked account, the account menu sends a new login to the one picked', async () => {
  waiting = [{ id: 'p2', name: '', detail: 'me@example.com', account: 'work@vault.example' }];
  accounts = [
    { id: 'a1', name: 'work@vault.example', detail: '' },
    { id: 'a2', name: 'home@vault.example', detail: '' },
  ];
  const host = document.createElement('div');
  document.body.append(host);
  const dispose = render(() => createComponent(SavePrompt, {}), host);
  await tick();
  const { t } = await import('../../lib/i18n');
  const trigger = host.querySelector<HTMLButtonElement>('.save-account')!;
  expect(trigger.textContent).toBe(t('save.toAccount', 'work@vault.example'));
  // ↓ opens the same menu as the email one, on the current account; ↓ and Enter pick the next.
  const key = (k: string) => trigger.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }));
  key('ArrowDown');
  expect(trigger.getAttribute('aria-expanded')).toBe('true');
  expect([...host.querySelectorAll('.save-accounts .row .name')].map((n) => n.textContent)).toEqual([
    'work@vault.example',
    'home@vault.example',
  ]);
  key('ArrowDown');
  key('Enter');
  expect(host.querySelector('.save-accounts')).toBeNull();
  expect(trigger.textContent).toBe(t('save.toAccount', 'home@vault.example'));

  host.querySelector<HTMLButtonElement>('.save-go')!.click();
  await tick();
  expect(send).toHaveBeenLastCalledWith({ command: 'pending', query: 'p2', field: 'save', account: 'a2' });
  expect(host.querySelector('.save-title')!.textContent).toBe('Saved to home@vault.example.');
  dispose();
});
