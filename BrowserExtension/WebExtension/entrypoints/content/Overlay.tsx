import { createEffect, createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { browser } from 'wxt/browser';
import { send } from '../../lib/send';
import { fillOtp, otpTargets, passwordFields, setValue, usernameFor, visible } from '../../lib/dom';
import type { Row } from '../../lib/protocol';
import { AppMark } from './AppMark';

const secondsLeft = (period: number, now: number) => period - (Math.floor(now / 1000) % period);

/** Seconds left in the code's period, drained like the app's ring. Codes are counted from the Unix epoch, so the
 *  page's clock and the app's agree on where a period starts. */
const Ring = (props: { period: number; now: number }) => {
  const left = () => secondsLeft(props.period, props.now);
  const circumference = 2 * Math.PI * 9;
  return (
    <span class="ring" data-urgent={left() <= 5} role="img" aria-label={`Code valid for ${left()} more seconds`}>
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

/** `pw`: the password field of a login form. `otp`: the field, or row of one-digit boxes, for a one-time code. */
type Target = { field: HTMLInputElement; pw?: HTMLInputElement; otp?: HTMLInputElement[] };
/** `at`: when the rows were fetched, so a code that has since rolled over is fetched again. */
type Menu = {
  target: Target;
  x: number;
  y: number;
  state: 'rows' | 'note';
  rows: Row[];
  note: string;
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
  let root!: HTMLDivElement;
  let asking = 0; // bumped on every ask and every close, so an answer that arrives late is dropped
  let autoShow: boolean | undefined; // the app's Browser setting, learned from its answers
  let autoCheckedAt = 0; // when the app last told us
  let autoOpened = false; // the menu opened by itself on focus: it must not take Enter from the page
  let navigated = false; // arrow keys moved the highlight, so Enter means "fill this one"
  let autoPausedUntil = 0; // the app didn't answer: don't ask again on every focus

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
    const reply = await send({ command: 'match', codes: true, reveal: true });
    refreshing = false;
    const now = menu();
    if (!now || now.target !== m.target || !reply.ok) return;
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
  }

  const place = (t: Target) => {
    tick();
    if (!t.field.isConnected) return { display: 'none' };
    const last = t.otp?.at(-1);
    if (last && t.otp && t.otp.length > 1) {
      // A row of one-digit boxes has no room inside: put the icon after the last one.
      const r = last.getBoundingClientRect();
      if (r.width < 8) return { display: 'none' };
      return { display: 'grid', left: `${r.right + 6}px`, top: `${r.top + (r.height - 22) / 2}px` };
    }
    if (!visible(t.field)) return { display: 'none' };
    const r = t.field.getBoundingClientRect();
    return { display: 'grid', left: `${r.right - 30}px`, top: `${r.top + (r.height - 22) / 2}px` };
  };

  /**
   * `click`: the icon in the field. `direct`: the keyboard shortcut, which fills at once when exactly one login matches.
   * `auto`: the field was focused; stays silent unless the app's setting is on and there is something to offer.
   */
  async function open(target: Target, mode: 'click' | 'direct' | 'auto' = 'click') {
    const auto = mode === 'auto';
    const r = target.field.getBoundingClientRect();
    const base = { target, x: r.left, y: r.bottom + 6, rows: [] as Row[], at: Date.now(), revealed: !auto };
    const mine = ++asking;
    autoOpened = false;
    if (!auto) setMenu({ ...base, state: 'note', note: 'Looking for logins…' });
    // Digits only when asked for: a field that merely took focus gets names and countdowns, never the code.
    const reply = await send({ command: 'match', codes: !!target.otp && !auto, reveal: !!target.otp && !auto });
    if (mine !== asking) return; // closed, or a newer ask took over
    if (reply.autoShow !== undefined) {
      autoShow = reply.autoShow;
      autoCheckedAt = Date.now();
    }
    if (auto) {
      if (!reply.ok) autoPausedUntil = Date.now() + 10_000;
      if (!reply.ok || !autoShow) return;
    } else if (!reply.ok) {
      return setMenu({ ...base, state: 'note', note: reply.error || "Triwarden isn't available." });
    }
    // A code field only offers the logins that have a code.
    const rows = target.otp ? (reply.rows ?? []).filter((row) => row.totpPeriod) : (reply.rows ?? []);
    if (!rows.length) {
      if (auto) return;
      const none = target.otp ? 'No login with a one-time code for this site.' : 'No logins for this site.';
      return setMenu({ ...base, state: 'note', note: none });
    }
    const only = rows.length === 1 ? rows[0] : undefined;
    if (mode === 'direct' && only) return choose(only, target);
    setActive(0);
    navigated = !auto;
    autoOpened = auto;
    setMenu({ ...base, state: 'rows', rows, note: '', at: Date.now() });
  }

  /** The keyboard shortcut: act on the field the user is in, else the first login or code field on the page. */
  function trigger() {
    const list = targets();
    const here = document.activeElement;
    const target = list.find((t) => t.field === here || t.otp?.includes(here as HTMLInputElement)) ?? list[0];
    if (target) void open(target, 'direct');
  }

  async function choose(row: Row, target: Target) {
    close();
    const filled = await send({ command: 'fill', query: row.id });
    if (!filled.ok) return;
    if (target.otp) return filled.totp ? fillOtp(target.otp, filled.totp) : undefined;
    const { field, pw } = target;
    setValue(pw ? usernameFor(pw) : field, filled.username);
    setValue(pw || passwordFields().find(visible), filled.password);
    // A page that asks for the code on the same form gets it too.
    const code = otpTargets()[0];
    if (filled.totp && code) fillOtp(code, filled.totp);
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
      if (menu() && !e.composedPath().includes(root.getRootNode() as ShadowRoot)) close();
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
      } else if (e.key === 'Enter' && navigated) {
        // A menu that opened by itself leaves Enter to the page until the arrow keys have picked a row.
        e.preventDefault();
        e.stopPropagation();
        const row = m.rows[active()];
        if (row) void choose(row, m.target);
      }
    };
    // Focus: open the suggestions when the app's setting asks for it; moving to any other field closes them.
    const focused = (e: FocusEvent) => {
      const el = e.target as Element;
      const t = targets().find((x) => x.field === el || x.otp?.includes(el as HTMLInputElement));
      if (!t) {
        if (autoOpened) close();
        return;
      }
      if (menu() || Date.now() < autoPausedUntil) return;
      // While the setting is off, look again every few seconds: turning it on in the app should work on pages
      // that are already open, without asking the app on every single focus.
      if (autoShow === false && Date.now() - autoCheckedAt < 5000) return;
      void open(t, 'auto');
    };
    // Frames with nothing to fill stay quiet, so the background can ask every frame of the tab.
    const asked = (message: unknown) => {
      if ((message as { trigger?: string } | null)?.trigger === 'fill') trigger();
    };
    browser.runtime.onMessage.addListener(asked);
    addEventListener('scroll', move, { passive: true, capture: true });
    addEventListener('resize', move, { passive: true });
    document.addEventListener('mousedown', outside, true);
    document.addEventListener('keydown', keys, true);
    document.addEventListener('focusin', focused, true);
    onCleanup(() => {
      clearTimeout(timer);
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
        {(t) => (
          <button
            class="key"
            type="button"
            title="Fill with Triwarden"
            aria-label="Fill with Triwarden"
            style={place(t)}
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => open(t)}
          >
            <AppMark size={22} />
          </button>
        )}
      </For>
      <Show when={menu()}>
        {(m) => (
          <div class="menu" role="menu" style={{ left: `${m().x}px`, top: `${m().y}px` }}>
            <div class="head">
              <AppMark size={16} />
              Triwarden
            </div>
            <Show when={m().state === 'rows'} fallback={<div class="note">{m().note}</div>}>
              <For each={m().rows}>
                {(row, i) => (
                  <div
                    class="row"
                    role="menuitem"
                    data-active={i() === active()}
                    onMouseEnter={() => setActive(i())}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => choose(row, m().target)}
                  >
                    <Avatar row={row} />
                    <span class="text">
                      <span class="name">{row.name}</span>
                      <Show when={row.detail}>
                        <span class="detail">{row.detail}</span>
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
                )}
              </For>
            </Show>
          </div>
        )}
      </Show>
    </div>
  );
}
