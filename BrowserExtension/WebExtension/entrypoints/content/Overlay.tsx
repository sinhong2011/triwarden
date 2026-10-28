import { createEffect, createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { send } from '../../lib/send';
import { fillOtp, otpTargets, passwordFields, setValue, usernameFor, visible } from '../../lib/dom';
import type { Row } from '../../lib/protocol';

const KeyIcon = () => (
  <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
    <path
      fill="currentColor"
      d="M14.5 3a6.5 6.5 0 0 0-6.2 8.5L3 16.8V21h4.2v-2.1h2.1v-2.1h2.1l1.1-1.1A6.5 6.5 0 1 0 14.5 3Zm1.6 3.6a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6Z"
    />
  </svg>
);

/** Seconds left in the code's period, drained like the app's ring. Codes are counted from the Unix epoch, so the
 *  page's clock and the app's agree on where a period starts. */
const Ring = (props: { period: number; now: number }) => {
  const left = () => props.period - (Math.floor(props.now / 1000) % props.period);
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

/** `pw`: the password field of a login form. `otp`: the field, or row of one-digit boxes, for a one-time code. */
type Target = { field: HTMLInputElement; pw?: HTMLInputElement; otp?: HTMLInputElement[] };
type Menu = { target: Target; x: number; y: number; state: 'rows' | 'note'; rows: Row[]; note: string };

export default function Overlay() {
  const [targets, setTargets] = createSignal<Target[]>([]);
  const [tick, setTick] = createSignal(0); // bumped on scroll/resize so positions are re-read
  const [menu, setMenu] = createSignal<Menu | null>(null);
  const [active, setActive] = createSignal(0); // the highlighted row, moved with the arrow keys
  const [now, setNow] = createSignal(Date.now()); // ticks once a second while the menu shows, for the countdowns
  let root!: HTMLDivElement;

  createEffect(() => {
    if (!menu()) return;
    setNow(Date.now());
    const timer = setInterval(() => setNow(Date.now()), 1000);
    onCleanup(() => clearInterval(timer));
  });

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
      // A row of one-digit boxes has no room inside: put the key after the last one.
      const r = last.getBoundingClientRect();
      if (r.width < 8) return { display: 'none' };
      return { display: 'grid', left: `${r.right + 6}px`, top: `${r.top + (r.height - 22) / 2}px` };
    }
    if (!visible(t.field)) return { display: 'none' };
    const r = t.field.getBoundingClientRect();
    return { display: 'grid', left: `${r.right - 28}px`, top: `${r.top + (r.height - 22) / 2}px` };
  };

  async function open(target: Target) {
    const r = target.field.getBoundingClientRect();
    const base = { target, x: r.left, y: r.bottom + 4, rows: [] as Row[] };
    setMenu({ ...base, state: 'note', note: 'Looking for logins…' });
    const reply = await send({ command: 'match' });
    if (!menu()) return; // closed while waiting
    if (!reply.ok) return setMenu({ ...base, state: 'note', note: reply.error || "Triwarden isn't available." });
    // A code field only offers the logins that have a code.
    const rows = target.otp ? (reply.rows ?? []).filter((row) => row.totpPeriod) : (reply.rows ?? []);
    if (!rows.length) {
      const none = target.otp ? 'No login with a one-time code for this site.' : 'No logins for this site.';
      return setMenu({ ...base, state: 'note', note: none });
    }
    setActive(0);
    setMenu({ ...base, state: 'rows', rows, note: '' });
  }

  async function choose(row: Row, target: Target) {
    setMenu(null);
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
      if (menu() && !e.composedPath().includes(root.getRootNode() as ShadowRoot)) setMenu(null);
    };
    const keys = (e: KeyboardEvent) => {
      const m = menu();
      if (!m) return;
      if (e.key === 'Escape') return void setMenu(null);
      if (m.state !== 'rows') return;
      const last = m.rows.length - 1;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        e.stopPropagation();
        setActive((i) => (e.key === 'ArrowDown' ? Math.min(i + 1, last) : Math.max(i - 1, 0)));
      } else if (e.key === 'Enter') {
        e.preventDefault();
        e.stopPropagation();
        const row = m.rows[active()];
        if (row) void choose(row, m.target);
      }
    };
    addEventListener('scroll', move, { passive: true, capture: true });
    addEventListener('resize', move, { passive: true });
    document.addEventListener('mousedown', outside, true);
    document.addEventListener('keydown', keys, true);
    onCleanup(() => {
      clearTimeout(timer);
      observer.disconnect();
      removeEventListener('scroll', move, true);
      removeEventListener('resize', move);
      document.removeEventListener('mousedown', outside, true);
      document.removeEventListener('keydown', keys, true);
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
            <KeyIcon />
          </button>
        )}
      </For>
      <Show when={menu()}>
        {(m) => (
          <div class="menu" role="menu" style={{ left: `${m().x}px`, top: `${m().y}px` }}>
            <div class="head">
              <KeyIcon />
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
                    <span class="badge" aria-hidden="true">
                      {row.name.trim().charAt(0)}
                    </span>
                    <span class="text">
                      <span class="name">{row.name}</span>
                      <Show when={row.detail}>
                        <span class="detail">{row.detail}</span>
                      </Show>
                    </span>
                    <Show when={row.totpPeriod}>{(period) => <Ring period={period()} now={now()} />}</Show>
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
