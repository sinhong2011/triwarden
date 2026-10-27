// Relays page requests to the Triwarden app (Safari: the extension's native handler; Chrome and Firefox: the
// bundled `tw` native-messaging host). The app decides everything: what matches, Touch ID, saving.
import { browser } from 'wxt/browser';
import { COMMANDS, type Reply } from '../lib/protocol';

const HOST = 'io.github.sinhong2011.triwarden';

export default defineBackground(() => {
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
