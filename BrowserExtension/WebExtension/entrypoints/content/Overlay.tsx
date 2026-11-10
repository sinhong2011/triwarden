import { createEffect, createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { browser } from 'wxt/browser';
import { shouldRequestTotpCopy } from '../../lib/after-fill';
import { replyErrorMessage } from '../../lib/bridge-status';
import { fillOtp, isRTL, otpTargets, passwordFields, setValue, usernameFor, visible } from '../../lib/dom';
import { t } from '../../lib/i18n';
import { iconPosition, menuLeft, menuVertical } from '../../lib/overlay-layout';
import type { Row } from '../../lib/protocol';
import { send } from '../../lib/send';
import { AppMark } from './AppMark';

const secondsLeft = (period: number, now: number) => period - (Math.floor(now / 1000) % period);

/** Seconds left in the code's period, drained like the app's ring. Codes are counted from the Unix epoch, so the
 *  page's clock and the app's agree on where a period starts. */
const Ring = (props: { period: number; now: number }) => {
  const left = () => secondsLeft(props.period, props.now);
  const circumference = 2 * Math.PI * 9;
  return (
    <span class="ring" data-urgent={left() <= 5} role="img" aria-label={t('overlay.codeValidFor', String(left()))}>
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle class="track" cx="12" cy="12" r="9" />
        <circle
          class="arc"
          cx="12"
          cy="12"
          r="9"
          transform="matrix(-1 0 0 1 24 0) rotate(-90 12 12)"
          stroke-dasharray={String(circumference)}
          stroke-dashoffset={String(circumference * (1 - left() / props.period))}
        />
      </svg>
      <span class="secs" aria-hidden="true">
        {left()}
      </span>
    </span>
  );
};

/** "485 • 657", like the app: the dot turns orange in the last seconds. Without digits (the menu opened by itself,
 *  before anyone asked to see a code) it shows "••• •••"; clicking the icon in the field reveals them. */
const Code = (props: { code?: string; urgent: boolean }) => {
  const digits = () => props.code ?? '000000';
  const half = () => Math.floor(digits().length / 2);
  return (
    <span class="code" data-urgent={props.urgent} data-masked={!props.code}>
      <span>{props.code ? digits().slice(0, half()) : '•••'}</span>
      <span class="dot" />
      <span>{props.code ? digits().slice(half()) : '•••'}</span>
    </span>
  );
};

/** The site's icon on a white tile, or its first letter when the app has no icon: the same tile as the vault list. */
const Avatar = (props: { row: Row }) => (
  <span class="avatar" aria-hidden="true">
    <Show when={props.row.icon} fallback={<span class="letter">{props.row.name.trim().charAt(0)}</span>}>
      {(icon) => <img src={`data:image/png;base64,${icon()}`} alt="" draggable={false} />}
    </Show>
  </span>
);

const ROW_HEIGHT = 50;
const MAX_ROWS = 5; // taller lists scroll
const HINT_HEIGHT = 30;
const MENU_WIDTH = 332;
const CODE_MENU_WIDTH = 392; // a code field's rows also hold the code and its ring, so the username needs more room

/** Rows are shown in two groups when a site has both logins with a passkey and logins without. */
const groupOf = (row: Row) => (row.passkey ? 'passkeys' : 'passwords');
const groupLabel = (group: ReturnType<typeof groupOf>) =>
  group === 'passkeys' ? t('overlay.passkeys') : t('overlay.passwords');

/** `pw`: the password field of a login form. `otp`: the field, or row of one-digit boxes, for a one-time code. */
type Target = { field: HTMLInputElement; pw?: HTMLInputElement; otp?: HTMLInputElement[] };
/** `at`: when the rows were fetched, so a code that has since rolled over is fetched again. */
type Menu = {
  target: Target;
  /** Opened by itself when a field took focus: starts with nothing highlighted and shows the key hints. */
  auto: boolean;
  state: 'rows' | 'note';
  rows: Row[];
  note: string;
  /** `vault_locked`: the note is a control that asks the app to show the unlock window again. */
  noteCode?: string;
  at: number;
  /** The person asked to see codes (icon or shortcut), so rolled-over codes are fetched again without asking. */
  revealed: boolean;
};

export default function Overlay() {
  const [targets, setTargets] = createSignal<Target[]>([]);
  const [tick, setTick] = createSignal(0); // bumped on scroll/resize so positions are re-read
  const [menu, setMenu] = createSignal<Menu | null>(null);
  const [active, setActive] = createSignal(0); // the highlighted row, moved with the arrow keys
  const [now, setNow] = createSignal(Date.now()); // ticks once a second while the menu shows, for the countdowns
  const [toast, setToast] = createSignal<string | null>(null); // quiet "Code copied" after fill, when the app did
  let root!: HTMLDivElement;
  let asking = 0; // bumped on every ask and every close, so an answer that arrives late is dropped
  let autoShow: boolean | undefined; // the app's Browser setting, learned from its answers
  let autoOpened = false; // the menu opened by itself on focus: it must not take Enter from the page
  let navigated = false; // arrow keys moved the highlight, so Enter means "fill this one"
  let filling = false; // we are putting values in fields: that moves focus, and must not open the menu again
  let toastTimer: number | undefined;

  const close = () => {
    asking++;
    autoOpened = false;
    setMenu(null);
  };

  // While a menu shows: tick the countdowns, and fetch codes again when one has rolled over.
  createEffect(() => {
    if (!menu()) return;
    setNow(Date.now());
    const timer = setInterval(() => {
      setNow(Date.now());
      const m = menu();
      if (m?.state === 'rows' && m.revealed && m.target.otp && m.rows.some((r) => r.totpPeriod && rolledOver(r.totpPeriod, m.at))) void refresh();
    }, 1000);
    onCleanup(() => clearInterval(timer));
  });

  const rolledOver = (period: number, since: number) => Math.floor(Date.now() / 1000 / period) > Math.floor(since / 1000 / period);

  let refreshing = false;
  async function refresh() {
    const m = menu();
    if (!m || refreshing) return;
    refreshing = true;
    const reply = await send({ command: 'match', codes: true, reveal: true, silent: true });
    refreshing = false;
    const now = menu();
    if (!now || now.target.field !== m.target.field || !reply.ok) return;
    const rows = (reply.rows ?? []).filter((r) => r.totpPeriod);
    if (rows.length) setMenu({ ...now, rows, at: Date.now() });
  }

  function scan() {
    const found = new Map<HTMLInputElement, Target>();
    for (const pw of passwordFields()) {
      if (!visible(pw) || /new-password/.test(pw.autocomplete || '')) continue;
      found.set(pw, { field: pw, pw });
      const user = usernameFor(pw);
      if (user && !found.has(user)) found.set(user, { field: user, pw });
    }
    for (const boxes of otpTargets()) {
      const first = boxes[0];
      if (first && !found.has(first)) found.set(first, { field: first, otp: boxes });
    }
    setTargets([...found.values()]);
    setTick((n) => n + 1);
    offerFor(document.activeElement);
  }

  const place = (t: Target) => {
    tick();
    if (!t.field.isConnected) return { display: 'none' };
    // In a right-to-left field the text starts at the right edge, so the icon goes on the left, out of its way.
    const rtl = isRTL(t.field);
    const last = t.otp?.at(-1);
    if (last && t.otp && t.otp.length > 1) {
      // A row of one-digit boxes has no room inside: put the icon after the last one.
      const r = last.getBoundingClientRect();
      if (r.width < 8) return { display: 'none' };
      return iconPosition(r, rtl, true);
    }
    if (!visible(t.field)) return { display: 'none' };
    const r = t.field.getBoundingClientRect();
    return iconPosition(r, rtl, false);
  };

  const menuHeight = (m: Menu) => {
    const shown = m.state === 'rows' ? Math.min(m.rows.length, MAX_ROWS) : 1;
    const groups = m.state === 'rows' && new Set(m.rows.map(groupOf)).size > 1 && !m.target.otp ? 2 : 0;
    return shown * ROW_HEIGHT + groups * 24 + 12 + (m.auto && m.state === 'rows' ? HINT_HEIGHT : 0);
  };

  /** Where the menu sits: prefer above the field (system AutoFill owns the space below); kept inside the window. */
  const menuPlace = (m: Menu) => {
    tick(); // scroll and resize move the field, and the menu goes with it
    const f = m.target.field;
    if (!f.isConnected) return null;
    const r = f.getBoundingClientRect();
    const wide = m.target.otp ? CODE_MENU_WIDTH : MENU_WIDTH;
    // Lined up with the field's start: its left edge, or its right edge when the field is right to left.
    const left = menuLeft(r, wide, isRTL(f), innerWidth);
    const vertical = menuVertical(r, menuHeight(m), innerHeight);
    return { left, width: `${wide}px`, vertical };
  };

  const menuStyle = (m: Menu) => {
    const place = menuPlace(m);
    if (!place) return { display: 'none' };
    const { left, width, vertical } = place;
    // Always `top` + clear `bottom`: never CSS `bottom` (Safari/WXT mis-resolve it on overlay hosts).
    return { left, width, top: vertical.top, bottom: 'auto' };
  };

  const menuAbove = (m: Menu) => menuPlace(m)?.vertical.above ?? false;

  /**
   * `click`: the icon in the field. `direct`: the keyboard shortcut, which fills at once when exactly one login matches.
   * `auto`: kept for the app's "show on focus" setting, but focus no longer opens the menu (system AutoFill collision).
   */
  async function open(target: Target, mode: 'click' | 'direct' | 'auto' = 'click') {
    const auto = mode === 'auto';
    const base = { target, auto, rows: [] as Row[], at: Date.now(), revealed: !auto };
    const mine = ++asking;
    autoOpened = false;
    if (!auto) setMenu({ ...base, state: 'note', note: t('overlay.lookingForLogins') });
    // Digits only when asked for: a field that merely took focus gets names and countdowns, never the code.
    const reply = await send({
      command: 'match',
      codes: !!target.otp && !auto,
      // Icon / shortcut: the person asked. `reveal` also survives an older `tw` that drops `foreground`.
      reveal: !auto,
      ...(auto ? { silent: true } : { foreground: true }),
    });
    if (mine !== asking) return; // closed, or a newer ask took over
    if (reply.autoShow !== undefined) autoShow = reply.autoShow;
    if (auto) {
      if (!reply.ok || !autoShow) return;
    } else if (!reply.ok) {
      return setMenu({
        ...base,
        state: 'note',
        note: replyErrorMessage(reply),
        noteCode: reply.code,
      });
    }
    // A code field only offers the logins that have a code.
    const found = target.otp ? (reply.rows ?? []).filter((row) => row.totpPeriod) : (reply.rows ?? []);
    // Two groups only when a site has both kinds; each keeps the app's order (exact address, then most recently filled).
    const mixed = !target.otp && found.some((row) => row.passkey) && found.some((row) => !row.passkey);
    const rows = mixed ? [...found.filter((r) => r.passkey), ...found.filter((r) => !r.passkey)] : found;
    if (!rows.length) {
      if (auto) return;
      const none = target.otp ? t('overlay.noOtpLogin') : t('overlay.noLogins');
      return setMenu({ ...base, state: 'note', note: none });
    }
    const only = rows.length === 1 ? rows[0] : undefined;
    if (mode === 'direct' && only) return choose(only, target);
    setActive(auto ? -1 : 0); // a menu that opened by itself highlights nothing until the mouse or an arrow key does
    navigated = !auto;
    autoOpened = auto;
    setMenu({ ...base, state: 'rows', rows, note: '', at: Date.now() });
  }

  /**
   * Whether the focused element is one of our fill targets. Also called after every scan: a field that was focused
   * before we looked (autofocus, a form that appeared under the cursor) fires no focus event.
   *
   * Does not open the suggestion menu on focus. Safari and Chrome draw their system AutoFill panel under the field
   * in the browser/OS layer, which always covers our shadow UI — so focus stays icon-only. Click the in-field mark
   * or use the keyboard shortcut / right-click menu to open Triwarden's list (placed above the field when possible).
   */
  function offerFor(el: Element | null): boolean {
    const t = targets().find((x) => x.field === el || x.otp?.includes(el as HTMLInputElement));
    if (!t) return false;
    // An auto-opened menu (legacy path) still follows focus between our fields.
    if (menu()?.auto && menu()!.target.field !== t.field) close();
    return true;
  }

  /**
   * The keyboard shortcut and the right-click menu: act on the field the user is in, else the first login or code field
   * on the page. With `rowId` (a login picked from the right-click menu) that login is filled, without asking again.
   */
  function trigger(rowId?: string) {
    const list = targets();
    const here = document.activeElement;
    const target = list.find((t) => t.field === here || t.otp?.includes(here as HTMLInputElement)) ?? list[0];
    if (!target) return;
    if (rowId) void choose({ id: rowId, name: '' }, target);
    else void open(target, 'direct');
  }

  function flash(note: string) {
    clearTimeout(toastTimer);
    setToast(note);
    toastTimer = window.setTimeout(() => setToast(null), 1800);
  }

  async function choose(row: Row, target: Target) {
    close();
    // Ask the app to copy with this fill when there is no OTP field (setting + totp live in the app).
    const copyTotp = shouldRequestTotpCopy(!!target.otp || otpTargets().length > 0);
    const filled = await send({
      command: 'fill',
      query: row.id,
      copyTotp,
    });
    if (!filled.ok) {
      if (filled.code === 'vault_locked') {
        setMenu({
          target,
          auto: false,
          state: 'note',
          rows: [],
          note: replyErrorMessage(filled),
          noteCode: filled.code,
          at: Date.now(),
          revealed: true,
        });
      }
      return;
    }
    filling = true;
    try {
      if (target.otp) {
        if (filled.totp) fillOtp(target.otp, filled.totp);
      } else {
        const { field, pw } = target;
        setValue(pw ? usernameFor(pw) : field, filled.username);
        setValue(pw || passwordFields().find(visible), filled.password);
        // A page that asks for the code on the same form gets it too.
        const code = otpTargets()[0];
        if (filled.totp && code) fillOtp(code, filled.totp);
      }
      if (filled.totpCopied) flash(t('overlay.codeCopied'));
    } finally {
      // Focus events from the fill arrive synchronously; give them a moment, then listen again.
      setTimeout(() => (filling = false), 400);
    }
  }

  onMount(() => {
    scan();
    let timer: number | undefined;
    const rescan = () => {
      clearTimeout(timer);
      timer = window.setTimeout(scan, 250);
    };
    const move = () => setTick((n) => n + 1);
    const observer = new MutationObserver(rescan);
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['type', 'style', 'class'],
    });
    const outside = (e: MouseEvent) => {
      // The overlay is a closed shadow root: listeners on the document see its host, never what is inside.
      const host = (root.getRootNode() as ShadowRoot).host;
      if (menu() && !e.composedPath().includes(host)) close();
    };
    const keys = (e: KeyboardEvent) => {
      const m = menu();
      if (!m) return;
      if (e.key === 'Escape') return void close();
      if (m.state !== 'rows') return;
      const last = m.rows.length - 1;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        e.stopPropagation();
        navigated = true;
        setActive((i) => (e.key === 'ArrowDown' ? Math.min(i + 1, last) : Math.max(i - 1, 0)));
        requestAnimationFrame(() => root.querySelector('.row[data-active="true"]')?.scrollIntoView({ block: 'nearest' }));
      } else if (e.key === 'Enter' && navigated) {
        // A menu that opened by itself leaves Enter to the page until the arrow keys have picked a row.
        e.preventDefault();
        e.stopPropagation();
        const row = m.rows[active()];
        if (row) void choose(row, m.target);
        else close();
      }
    };
    // Focus: track whether the field is ours (icon stays); moving off an auto-opened menu closes it.
    const focused = (e: FocusEvent) => {
      if (!offerFor(e.target as Element) && autoOpened) close();
    };
    // Frames with nothing to fill stay quiet, so the background can ask every frame of the tab.
    const asked = (message: unknown, _sender: unknown, reply: (value: unknown) => void) => {
      const m = message as { trigger?: string; row?: string; ask?: string } | null;
      if (m?.ask === 'url') {
        if (window === window.top) reply(location.href); // the right-click menu is built for the page's own address
      } else if (m?.trigger === 'fill') {
        trigger(m.row);
      }
      return false;
    };
    browser.runtime.onMessage.addListener(asked);
    addEventListener('scroll', move, { passive: true, capture: true });
    addEventListener('resize', move, { passive: true });
    document.addEventListener('mousedown', outside, true);
    document.addEventListener('keydown', keys, true);
    document.addEventListener('focusin', focused, true);
    onCleanup(() => {
      clearTimeout(timer);
      clearTimeout(toastTimer);
      browser.runtime.onMessage.removeListener(asked);
      observer.disconnect();
      removeEventListener('scroll', move, true);
      removeEventListener('resize', move);
      document.removeEventListener('mousedown', outside, true);
      document.removeEventListener('keydown', keys, true);
      document.removeEventListener('focusin', focused, true);
    });
  });

  return (
    <div ref={root}>
      <For each={targets()}>
        {(target) => (
          <button
            class="key"
            type="button"
            title={t('overlay.fillWithTriwarden')}
            aria-label={t('overlay.fillWithTriwarden')}
            style={place(target)}
            on:mousedown={(e) => e.preventDefault()}
            on:click={() => open(target)}
          >
            <AppMark size={22} />
          </button>
        )}
      </For>
      <Show when={toast()}>
        {(text) => (
          <div class="fill-toast" role="status" aria-live="polite">
            {text()}
          </div>
        )}
      </Show>
      <Show when={menu()}>
        {(m) => {
          // Two logins with the same name are told apart by their username, which then leads the row.
          const dupes = () => {
            const seen = new Set<string>(), twice = new Set<string>();
            for (const r of m().rows) (seen.has(r.name) ? twice : seen).add(r.name);
            return twice;
          };
          const mixed = () => !m().target.otp && new Set(m().rows.map(groupOf)).size > 1;
          return (
            <div class="menu" role="menu" style={menuStyle(m())} data-rtl={isRTL(m().target.field)} data-above={menuAbove(m())}>
              <Show
                when={m().state === 'rows'}
                fallback={
                  <Show
                    when={m().noteCode === 'vault_locked'}
                    fallback={
                      <div class="note" dir="auto">
                        {m().note}
                      </div>
                    }
                  >
                    <button
                      class="note note-action"
                      type="button"
                      dir="auto"
                      title={t('overlay.openToUnlock')}
                      on:mousedown={(e) => e.preventDefault()}
                      on:click={() => open(m().target)}
                    >
                      {m().note}
                    </button>
                  </Show>
                }
              >
                <div class="list">
                  <For each={m().rows}>
                    {(row, i) => (
                      <>
                        <Show when={mixed() && (i() === 0 || groupOf(m().rows[i() - 1]!) !== groupOf(row))}>
                          <div class="group">{groupLabel(groupOf(row))}</div>
                        </Show>
                        <div
                          class="row"
                          role="menuitem"
                          data-active={i() === active()}
                          onMouseEnter={() => setActive(i())}
                          on:mousedown={(e) => e.preventDefault()}
                          on:click={() => choose(row, m().target)}
                        >
                          <Avatar row={row} />
                          <span class="text">
                            {/* Names and usernames can be in any script: each takes its own direction. */}
                            <span class="name" dir="auto">
                              {dupes().has(row.name) && row.detail ? row.detail : row.name}
                            </span>
                            <Show when={dupes().has(row.name) ? row.name : row.detail}>
                              {(sub) => (
                                <span class="detail" dir="auto">
                                  {sub()}
                                </span>
                              )}
                            </Show>
                          </span>
                          {/* The code and its countdown belong to a code field only. */}
                          <Show when={m().target.otp && row.totpPeriod}>
                            {(period) => (
                              <>
                                <Code code={row.code} urgent={secondsLeft(period(), now()) <= 5} />
                                <Ring period={period()} now={now()} />
                              </>
                            )}
                          </Show>
                        </div>
                      </>
                    )}
                  </For>
                </div>
                <Show when={m().auto}>
                  <div class="hint">
                    <kbd>↑</kbd>
                    <kbd>↓</kbd> {t('overlay.hintChoose')} <kbd>↵</kbd> {t('overlay.hintFill')} <kbd>esc</kbd>{' '}
                    {t('overlay.hintClose')}
                  </div>
                </Show>
              </Show>
            </div>
          );
        }}
      </Show>
    </div>
  );
}
