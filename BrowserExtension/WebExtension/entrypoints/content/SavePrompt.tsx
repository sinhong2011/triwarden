import { createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { browser } from 'wxt/browser';
import type { Row } from '../../lib/protocol';
import { replyErrorMessage } from '../../lib/bridge-status';
import { t } from '../../lib/i18n';
import { send } from '../../lib/send';
import { AppMark } from './AppMark';

/**
 * The page's own "Save login?" card, top right like 1Password and Bitwarden, so a sign-up or a new password is not
 * missed in the menu bar. It shows what the app is holding for this tab's login (the same entries as the bell), so it
 * comes back after the page navigates or reloads until answered. Top frame only. The app is asked only when the
 * background says a login waits in this tab (it pings after any save), never on every page load.
 */
const chevron = (
  <svg viewBox="0 0 16 16" width="10" height="10" aria-hidden="true">
    <path d="M4 6l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
  </svg>
);

export default function SavePrompt() {
  const [row, setRow] = createSignal<Row | null>(null);
  /** The site the login was typed on (an iframe's or the page before a redirect), from the background. */
  const [site, setSite] = createSignal('');
  /** Saved: the card says so and goes. */
  const [done, setDone] = createSignal<string | null>(null);
  /** Failed: said under the question, with Save / Not Now still there to try again or let it go. */
  const [error, setError] = createSignal<string | null>(null);
  const [busy, setBusy] = createSignal(false);
  /** More than one unlocked account: where a new login can go, and the one picked here (else the one the app named). */
  const [accounts, setAccounts] = createSignal<Row[]>([]);
  const [chosen, setChosen] = createSignal<Row | null>(null);
  /** The account menu, the same menu as the email one: open, and the row ↑/↓ is on. */
  const [picking, setPicking] = createSignal(false);
  const [active, setActive] = createSignal(-1);
  /** Closed with × or Escape on this page: stays in the app's bell, not shown again here until something new waits. */
  const hidden = new Set<string>();
  let asking = 0;
  let promptEl: HTMLDivElement | undefined;

  async function check() {
    const mine = ++asking;
    const url = (await browser.runtime.sendMessage({ ask: 'saves' }).catch(() => null)) as string | null;
    const reply = url ? await send({ command: 'pending' }) : null;
    if (mine !== asking) return;
    const next = (reply?.ok ? (reply.rows ?? []) : []).filter((r) => !hidden.has(r.id)).at(-1) ?? null;
    if (next?.id !== row()?.id) {
      setDone(null);
      setError(null);
      setChosen(null);
      setPicking(false);
    }
    setAccounts(reply?.ok ? (reply.accounts ?? []) : []);
    // The picked account was locked meanwhile: back to the one the app names, instead of a Save that keeps failing.
    if (!accounts().some((a) => a.id === chosen()?.id)) setChosen(null);
    if (url) setSite(new URL(url).hostname);
    setRow(next);
  }

  async function answer(r: Row, save: boolean) {
    if (busy()) return;
    setBusy(true);
    const account = save ? chosen()?.id : undefined;
    const reply = await send({ command: 'pending', query: r.id, field: save ? 'save' : 'never', ...(account && { account }) });
    setBusy(false);
    if (!reply.ok) return setError(replyErrorMessage(reply));
    hidden.add(r.id);
    if (save) {
      const to = chosen()?.name ?? r.account;
      setDone(r.name ? t('save.updated') : to ? t('save.savedTo', to) : t('save.saved'));
      setTimeout(() => void check(), 1600);
    } else void check();
  }

  /** A new login can go to another unlocked account; an update stays in the account that has the login. */
  const canPick = (r: Row) => !r.name && accounts().length > 1;
  const pick = (a: Row) => {
    setChosen(a);
    setPicking(false);
  };
  const openPicker = () => {
    setActive(Math.max(0, accounts().findIndex((a) => a.name === (chosen()?.name ?? row()?.account))));
    setPicking(true);
  };
  const pickerKeys = (e: KeyboardEvent) => {
    if (!picking()) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        openPicker();
      }
      return;
    }
    const list = accounts();
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((i) => (e.key === 'ArrowDown' ? Math.min(i + 1, list.length - 1) : Math.max(i - 1, 0)));
    } else if (e.key === 'Enter' && list[active()]) {
      e.preventDefault();
      pick(list[active()]!);
    }
  };

  const close = (r: Row) => {
    hidden.add(r.id);
    setRow(null);
  };

  onMount(() => {
    void check();
    const asked = (message: unknown) => {
      if ((message as { trigger?: string } | null)?.trigger === 'saves') void check();
      return false;
    };
    const keys = (e: KeyboardEvent) => {
      const r = row();
      if (e.key !== 'Escape' || !r) return;
      if (picking()) setPicking(false);
      else close(r);
    };
    // A click outside closes the account menu, as with the email menu.
    const outside = (e: MouseEvent) => {
      if (picking() && promptEl && !e.composedPath().includes((promptEl.getRootNode() as ShadowRoot).host)) setPicking(false);
    };
    browser.runtime.onMessage.addListener(asked);
    document.addEventListener('keydown', keys, true);
    document.addEventListener('mousedown', outside, true);
    onCleanup(() => {
      browser.runtime.onMessage.removeListener(asked);
      document.removeEventListener('keydown', keys, true);
      document.removeEventListener('mousedown', outside, true);
    });
  });

  return (
    <Show when={row()}>
      {(r) => (
        <div
          ref={(el) => {
            promptEl = el;
          }}
          class="save-prompt"
          role="region"
          aria-label={t('save.dialog')}
        >
          <div class="save-card" dir="auto">
            <AppMark size={28} />
            {/* Announced when it appears or changes, without taking focus from the page. */}
            <div class="save-text" role="status" aria-live="polite">
              <Show when={!done()} fallback={<span class="save-title">{done()}</span>}>
                <span class="save-title">
                  {r().name ? t('save.updateFor', r().name) : t('save.saveFor', site() || location.hostname)}
                </span>
                <span class="save-detail">{r().detail || t('save.noUsername')}</span>
                <Show when={r().account}>
                  {(a) => (
                    <Show
                      when={canPick(r())}
                      fallback={<span class="save-detail">{t('save.toAccount', a())}</span>}
                    >
                      <button
                        type="button"
                        class="save-detail save-account"
                        aria-haspopup="menu"
                        aria-expanded={picking()}
                        aria-activedescendant={picking() && active() >= 0 ? `save-account-${active()}` : undefined}
                        disabled={busy()}
                        on:click={() => (picking() ? setPicking(false) : openPicker())}
                        on:keydown={pickerKeys}
                      >
                        <span class="save-account-name">{t('save.toAccount', chosen()?.name ?? a())}</span>
                        {chevron}
                      </button>
                    </Show>
                  )}
                </Show>
                <Show when={error()}>
                  <span class="save-error">{error()}</span>
                </Show>
              </Show>
            </div>
            <button
              type="button"
              class="bridge-banner-dismiss"
              aria-label={t('save.close')}
              title={t('save.close')}
              on:click={() => close(r())}
            >
              ×
            </button>
          </div>
          <Show when={picking() && !done()}>
            <div
              class="menu save-accounts"
              role="menu"
              aria-label={t('save.chooseAccount')}
              on:mousedown={(e) => e.preventDefault()}
            >
              <div class="list">
                <div class="group">{t('save.chooseAccount')}</div>
                <For each={accounts()}>
                  {(a, i) => (
                    <div
                      id={`save-account-${i()}`}
                      class="row"
                      role="menuitemradio"
                      aria-checked={a.name === (chosen()?.name ?? r().account)}
                      data-active={i() === active()}
                      onMouseEnter={() => setActive(i())}
                      on:click={() => pick(a)}
                    >
                      <span class="text">
                        <span class="name" dir="auto">
                          {a.name}
                        </span>
                      </span>
                    </div>
                  )}
                </For>
              </div>
            </div>
          </Show>
          <Show when={!done()}>
            <div class="save-actions">
              <button type="button" class="save-later" disabled={busy()} on:click={() => void answer(r(), false)}>
                {t('save.notNow')}
              </button>
              <button type="button" class="save-go" disabled={busy()} on:click={() => void answer(r(), true)}>
                {r().name ? t('save.update') : t('save.save')}
              </button>
            </div>
          </Show>
        </div>
      )}
    </Show>
  );
}
