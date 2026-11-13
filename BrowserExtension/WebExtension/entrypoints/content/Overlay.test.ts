// @vitest-environment jsdom
import { createComponent, render } from 'solid-js/web';
import { expect, it, vi } from 'vitest';

vi.mock('wxt/browser', () => ({
  browser: { runtime: { onMessage: { addListener: vi.fn(), removeListener: vi.fn() } } },
}));
vi.mock('../../lib/send', () => ({ send: vi.fn(async () => ({ ok: true, rows: [] })) }));
const { default: Overlay } = await import('./Overlay');
HTMLElement.prototype.getBoundingClientRect = () => new DOMRect(0, 200, 300, 40);
const tick = () => new Promise((r) => setTimeout(r, 0));

const keys = async (html: string) => {
  document.body.innerHTML = html;
  const host = document.createElement('div');
  document.body.append(host);
  const dispose = render(() => createComponent(Overlay, {}), host);
  await tick();
  const count = host.querySelectorAll('.key').length;
  dispose();
  return count;
};

it('leaves sign-up fields to the generate overlay and still offers vault fill on a login', async () => {
  expect(await keys(`<form><input name=user><input type=password name=pass><button type=submit>Sign up</button></form>`)).toBe(0);
  expect(await keys(`<form><input name=user><input type=password name=pass><button type=submit>Log in</button></form>`)).toBe(2);
});
