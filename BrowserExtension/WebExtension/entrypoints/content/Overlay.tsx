import { createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { send } from '../../lib/send';
import { passwordFields, setValue, usernameFor, visible } from '../../lib/dom';
import type { Row } from '../../lib/protocol';

const KeyIcon = () => (
  <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
    <path
      fill="currentColor"
      d="M14.5 3a6.5 6.5 0 0 0-6.2 8.5L3 16.8V21h4.2v-2.1h2.1v-2.1h2.1l1.1-1.1A6.5 6.5 0 1 0 14.5 3Zm1.6 3.6a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6Z"
    />
  </svg>
);

type Target = { field: HTMLInputElement; pw?: HTMLInputElement };
type Menu = { target: Target; x: number; y: number; state: 'loading' | 'rows' | 'note'; rows: Row[]; note: string };

export default function Overlay() {
  const [targets, setTargets] = createSignal<Target[]>([]);
  const [tick, setTick] = createSignal(0); // bumped on scroll/resize so positions are re-read
  const [menu, setMenu] = createSignal<Menu | null>(null);
  let root!: HTMLDivElement;

  function scan() {
    const found = new Map<HTMLInputElement, Target>();
    for (const pw of passwordFields()) {
      if (!visible(pw) || /new-password/.test(pw.autocomplete || '')) continue;
      found.set(pw, { field: pw, pw });
      const user = usernameFor(pw);
      if (user && !found.has(user)) found.set(user, { field: user, pw });
    }
    setTargets([...found.values()]);
    setTick((n) => n + 1);
  }

  const place = (t: Target) => {
    tick();
    if (!t.field.isConnected || !visible(t.field)) return { display: 'none' };
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
    if (!reply.rows?.length) return setMenu({ ...base, state: 'note', note: 'No logins for this site.' });
    setMenu({ ...base, state: 'rows', rows: reply.rows, note: '' });
    queueMicrotask(() => root.querySelector<HTMLElement>('.row')?.focus());
  }

  async function choose(row: Row, target: Target) {
    setMenu(null);
    const filled = await send({ command: 'fill', query: row.id });
    if (!filled.ok) return;
    const { field, pw } = target;
    setValue(pw ? usernameFor(pw) : field, filled.username);
    setValue(pw || passwordFields().find(visible), filled.password);
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
    const escape = (e: KeyboardEvent) => e.key === 'Escape' && setMenu(null);
    addEventListener('scroll', move, { passive: true, capture: true });
    addEventListener('resize', move, { passive: true });
    document.addEventListener('mousedown', outside, true);
    document.addEventListener('keydown', escape, true);
    onCleanup(() => {
      clearTimeout(timer);
      observer.disconnect();
      removeEventListener('scroll', move, true);
      removeEventListener('resize', move);
      document.removeEventListener('mousedown', outside, true);
      document.removeEventListener('keydown', escape, true);
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
            <div class="head">Triwarden</div>
            <Show when={m().state === 'rows'} fallback={<div class="note">{m().note}</div>}>
              <For each={m().rows}>
                {(row) => (
                  <div
                    class="row"
                    role="menuitem"
                    tabindex="0"
                    onClick={() => choose(row, m().target)}
                    onKeyDown={(e) => e.key === 'Enter' && choose(row, m().target)}
                  >
                    <span>{row.name}</span>
                    <small>{row.detail || ''}</small>
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
