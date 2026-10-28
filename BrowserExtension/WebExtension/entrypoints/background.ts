// Relays page requests to the Triwarden app (Safari: the extension's native handler; Chrome and Firefox: the
// bundled `tw` native-messaging host). The app decides everything: what matches, Touch ID, saving.
import { browser } from 'wxt/browser';
import { COMMANDS, type Reply } from '../lib/protocol';

const HOST = 'io.github.sinhong2011.triwarden';

export default defineBackground(() => {
  // Right-click menu, like the password managers': Triwarden > Autofill login / Copy username / Copy password / Copy
  // verification code > one entry per login of the page's site. Chrome has no "menu is about to show" event, so the
  // entries are built ahead for the active tab (when it changes or finishes loading) from a names-only `match`: no
  // Touch ID until an entry is picked. Safari has no context menus API.
  if (browser.contextMenus) setUpContextMenu();

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

type Login = { id: string; label: string; totp: boolean };

const ACTIONS = [
  { id: 'fill', title: 'Autofill login', field: undefined, needsCode: false },
  { id: 'username', title: 'Copy username', field: 'username', needsCode: false },
  { id: 'password', title: 'Copy password', field: 'password', needsCode: false },
  { id: 'totp', title: 'Copy verification code', field: 'totp', needsCode: true },
] as const;

function setUpContextMenu() {
  let generation = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  /** The top frame's address. Asked of the page itself: the `tabs` permission (every tab's address) is not needed. */
  const pageUrl = async (tabId: number): Promise<string | undefined> => {
    try {
      const url = await browser.tabs.sendMessage(tabId, { ask: 'url' }, { frameId: 0 });
      return typeof url === 'string' && /^https?:/.test(url) ? url : undefined;
    } catch {
      return undefined; // no content script here (browser pages, the web store, a tab still loading)
    }
  };

  const label = (row: { name: string; detail?: string }) => {
    const text = row.detail ? `${row.name} (${row.detail})` : row.name;
    return text.replace(/&/g, '&&'); // a lone & marks a keyboard mnemonic in menu titles
  };

  async function rebuild(tabId: number) {
    const mine = ++generation;
    const url = await pageUrl(tabId);
    if (mine !== generation) return;
    let logins: Login[] = [];
    let problem = '';
    if (url) {
      try {
        const reply = (await browser.runtime.sendNativeMessage(HOST, { command: 'match', url })) as Reply | undefined;
        if (reply?.ok) logins = (reply.rows ?? []).map((r) => ({ id: r.id, label: label(r), totp: !!r.totpPeriod }));
        else problem = reply?.error ?? "Triwarden isn't available.";
      } catch (error) {
        problem = String((error as Error)?.message ?? error);
      }
    }
    if (mine !== generation) return;
    await browser.contextMenus.removeAll();
    if (mine !== generation || !url) return; // nothing to offer on pages we do not run on

    browser.contextMenus.create({ id: 'root', title: 'Triwarden', contexts: ['all'] });
    const empty = (parentId: string, title: string) =>
      browser.contextMenus.create({ id: `${parentId}:none`, parentId, title, enabled: false, contexts: ['all'] });
    if (problem || !logins.length) {
      empty('root', problem ? problem.slice(0, 60) : 'No logins for this site');
      return;
    }
    for (const action of ACTIONS) {
      const rows = action.needsCode ? logins.filter((l) => l.totp) : logins;
      browser.contextMenus.create({ id: action.id, parentId: 'root', title: action.title, contexts: ['all'] });
      if (!rows.length) empty(action.id, 'No login has a code');
      for (const login of rows) {
        browser.contextMenus.create({ id: `${action.id}:${login.id}`, parentId: action.id, title: login.label, contexts: ['all'] });
      }
    }
  }

  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
      if (tab?.id != null) void rebuild(tab.id);
    }, 250);
  };
  browser.tabs.onActivated.addListener(schedule);
  browser.tabs.onUpdated.addListener((_id, change, tab) => {
    if (change.status === 'complete' && tab.active) schedule();
  });
  browser.runtime.onInstalled.addListener(schedule);
  browser.runtime.onStartup.addListener(schedule);

  browser.contextMenus.onClicked.addListener((info, tab) => {
    const [actionId, ...rest] = String(info.menuItemId).split(':');
    const loginId = rest.join(':');
    const action = ACTIONS.find((a) => a.id === actionId);
    if (!action || !loginId || loginId === 'none' || tab?.id == null) return;
    if (!action.field) {
      // On a field only its own frame answers; elsewhere every frame hears it and the one with a form fills.
      const frameId = info.editable ? (info as { frameId?: number }).frameId : undefined;
      browser.tabs
        .sendMessage(tab.id, { trigger: 'fill', row: loginId }, frameId != null ? { frameId } : undefined)
        .catch(() => {});
      return;
    }
    // Copying is the app's job: the value goes to the clipboard from there and never passes through the extension.
    const url = info.pageUrl ?? tab.url;
    void Promise.resolve(browser.runtime.sendNativeMessage(HOST, { command: 'copy', query: loginId, field: action.field, url })).catch(
      () => {},
    );
  });
}
