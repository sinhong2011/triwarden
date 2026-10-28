// Relays page requests to the Triwarden app (Safari: the extension's native handler; Chrome and Firefox: the
// bundled `tw` native-messaging host). The app decides everything: what matches, Touch ID, saving.
import { browser } from 'wxt/browser';
import { COMMANDS, type Reply } from '../lib/protocol';

const HOST = 'io.github.sinhong2011.triwarden';

export default defineBackground(() => {
  // Right-click in a field: "Fill with Triwarden". It acts like the shortcut, in the frame that was clicked.
  browser.runtime.onInstalled.addListener(() => {
    browser.contextMenus.removeAll(() => {
      browser.contextMenus.create({ id: 'fill-login', title: 'Fill with Triwarden', contexts: ['editable'] });
    });
  });
  browser.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId !== 'fill-login' || tab?.id == null) return;
    const frameId = (info as { frameId?: number }).frameId;
    browser.tabs
      .sendMessage(tab.id, { trigger: 'fill' }, frameId != null ? { frameId } : undefined)
      .catch(() => {});
  });

  // The fill shortcut (see `commands` in wxt.config.ts): every frame of the tab hears it, and the ones with a
  // login or code field answer by filling or opening the menu.
  browser.commands.onCommand.addListener(async (command, tab) => {
    if (command !== 'fill-login') return;
    const id = tab?.id ?? (await browser.tabs.query({ active: true, currentWindow: true }))[0]?.id;
    if (id != null) await browser.tabs.sendMessage(id, { trigger: 'fill' }).catch(() => {});
  });

  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message || !COMMANDS.has(message.command) || !sender.tab) return false;
    // The page URL comes from the browser, not from the page, so a frame can't claim another site.
    const url = sender.url ?? sender.tab.url;
    const request = { ...message, url };
    Promise.resolve(browser.runtime.sendNativeMessage(HOST, request))
      .then((reply: Reply | undefined) => sendResponse(reply ?? { ok: false, error: 'No answer from Triwarden.' }))
      .catch((error: unknown) =>
        sendResponse({ ok: false, error: String((error as Error)?.message ?? error) }),
      );
    return true; // async response
  });
});
