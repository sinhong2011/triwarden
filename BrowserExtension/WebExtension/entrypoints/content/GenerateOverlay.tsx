import { createSignal, For, onCleanup, onMount, Show } from 'solid-js';
import { replyErrorMessage } from '../../lib/bridge-status';
import { generateTargets, isRTL, setValue, usernameFor, visible, wantsEmail, type GenerateTarget } from '../../lib/dom';
import { t } from '../../lib/i18n';
import { applyMenuDrag, generateMenuPlace, iconPosition, menuLeft, menuVertical } from '../../lib/overlay-layout';
import type { Request } from '../../lib/protocol';
import { send } from '../../lib/send';
import { AppMark } from './AppMark';

/**
 * Sign-up / change-password UI, in every browser (vault pick/fill on ordinary login fields is Safari's system AutoFill
 * or, elsewhere, the fill overlay). Icons appear only on generate-relevant password fields (new-password,
 * change-password, registration), never on the confirm field: generating fills both. Using a suggestion offers to save
 * the login right away when the username is already typed; otherwise `watchForSubmits` offers it on submit.
 *
 * On a sign-up the username / email field gets its own icon: your emails from the vault, or a new username / private
 * address from the app's username generator.
 *
 * The generate dialog mirrors the app's compact Generator popover (Length / Include chips / strength / Use),
 * while staying an in-page overlay with drag-to-move + per-origin place memory. Generation always runs in the
 * Triwarden app (same PasswordGenerator / PassphraseGenerator prefs).
 */

type Target = GenerateTarget;
type Kind = 'password' | 'passphrase';

type PasswordOpts = {
  length: number;
  uppercase: boolean;
  lowercase: boolean;
  digits: boolean;
  symbols: boolean;
  avoidAmbiguous: boolean;
  minNumbers: number;
  minSpecial: number;
};

type PassphraseOpts = {
  words: number;
  separator: string;
  capitalize: boolean;
  includeNumber: boolean;
};

/** The menu shows a ready value the moment it opens, like a password manager's inline generator. */
type Menu = {
  target: Target;
  kind: Kind;
  value?: string;
  error?: string;
  entropyBits?: number;
};

const MENU_WIDTH = 360;
const WHO_WIDTH = 300;

/** Absolute viewport place of the password menu while it is dragged. */
type MenuPos = { left: number; top: number };

/** The username / email menu: your emails (unlocked vault only) and a freshly generated one. */
type Who = {
  /** The sign-up: its username field gets the name; its empty password a strong one, like 1Password. */
  target: Target;
  emails: string[];
  value?: string;
  note?: string;
};
/** Approximate height with password options open; used for placement + drag clamp until the node is measured. */
const MENU_HEIGHT = 460;

const DEFAULT_PASSWORD: PasswordOpts = {
  length: 20,
  uppercase: true,
  lowercase: true,
  digits: true,
  symbols: true,
  avoidAmbiguous: true,
  minNumbers: 1,
  minSpecial: 1,
};

const DEFAULT_PASSPHRASE: PassphraseOpts = {
  words: 6,
  separator: '-',
  capitalize: false,
  includeNumber: false,
};

/** Digits and symbols in their own colours, so 0/O and l/1 read apart at a glance (as in Passwords and Bitwarden). */
function Pretty(props: { value: string }) {
  return (
    <For each={[...props.value]}>
      {(ch) => <span data-c={/\d/.test(ch) ? 'digit' : /[A-Za-z\s]/.test(ch) ? undefined : 'symbol'}>{ch}</span>}
    </For>
  );
}

function strengthLevel(bits: number): { level: number; labelKey: 'gen.weak' | 'gen.fair' | 'gen.strong' | 'gen.veryStrong' } {
  if (bits < 40) return { level: 1, labelKey: 'gen.weak' };
  if (bits < 64) return { level: 2, labelKey: 'gen.fair' };
  if (bits < 90) return { level: 3, labelKey: 'gen.strong' };
  return { level: 4, labelKey: 'gen.veryStrong' };
}

function Stepper(props: {
  value: number;
  min: number;
  max: number;
  onChange: (n: number) => void;
  label: string;
}) {
  const clamp = (n: number) => Math.min(props.max, Math.max(props.min, n));
  return (
    <div class="gen-stepper" role="group" aria-label={props.label}>
      <button
        type="button"
        aria-label={t('gen.decrease', props.label)}
        disabled={props.value <= props.min}
        on:click={(e) => {
          e.stopPropagation();
          props.onChange(clamp(props.value - 1));
        }}
      >
        −
      </button>
      <span aria-live="polite">{props.value}</span>
      <button
        type="button"
        aria-label={t('gen.increase', props.label)}
        disabled={props.value >= props.max}
        on:click={(e) => {
          e.stopPropagation();
          props.onChange(clamp(props.value + 1));
        }}
      >
        +
      </button>
    </div>
  );
}

export default function GenerateOverlay() {
  let lastKind: Kind = 'password'; // this page remembers the person's last choice while the overlay stays mounted
  const [targets, setTargets] = createSignal<Target[]>([]);
  const [tick, setTick] = createSignal(0);
  const [menu, setMenu] = createSignal<Menu | null>(null);
  /**
   * Where the person dragged the open menu. Null: it follows its field (scroll, resize). Never kept after closing:
   * the menu always opens next to the field it belongs to.
   */
  const [menuPos, setMenuPos] = createSignal<MenuPos | null>(null);
  const [dragging, setDragging] = createSignal(false);
  const [password, setPassword] = createSignal<PasswordOpts>({ ...DEFAULT_PASSWORD });
  const [passphrase, setPassphrase] = createSignal<PassphraseOpts>({ ...DEFAULT_PASSPHRASE });
  /** Once the app has echoed options for a kind, further generates send the full set so prefs stay in sync. */
  const [seededPassword, setSeededPassword] = createSignal(false);
  const [seededPassphrase, setSeededPassphrase] = createSignal(false);
  const [copied, setCopied] = createSignal(false);
  const [updating, setUpdating] = createSignal(false);
  const [who, setWho] = createSignal<Who | null>(null);
  /** The row the arrow keys are on; -1 until they are used, so Enter still submits the page's form. */
  const [whoActive, setWhoActive] = createSignal(-1);
  let askingWho = 0;
  const whoField = (w: Who) => w.target.username!;
  /** What the menu offers, in order: your emails, then the generated one. */
  const whoChoices = (w: Who) => (w.value ? [...w.emails, w.value] : w.emails);
  let root!: HTMLDivElement;
  let menuEl: HTMLDivElement | undefined;
  let asking = 0;
  let dragSession: { pointerId: number; startX: number; startY: number; origLeft: number; origTop: number } | null =
    null;
  let copyTimer: number | undefined;
  let regenTimer: number | undefined;

  const menuHeight = () => menuEl?.offsetHeight || MENU_HEIGHT;

  /** Anchor under the field icon (or confirm), ignoring any dragged place. */
  function anchorPlace(m: Menu): MenuPos | null {
    tick();
    const f = m.target.field;
    if (!f.isConnected) return null;
    const c = m.target.confirm;
    const confirm = c?.isConnected && visible(c) ? c.getBoundingClientRect() : null;
    const { left, vertical } = generateMenuPlace(
      f.getBoundingClientRect(),
      confirm,
      MENU_WIDTH,
      menuHeight(),
      { width: innerWidth, height: innerHeight },
      isRTL(f),
    );
    return { left: Number.parseFloat(left), top: Number.parseFloat(vertical.top) };
  }

  const menuAbove = (m: Menu) => {
    tick();
    const f = m.target.field;
    if (!f.isConnected) return false;
    const c = m.target.confirm;
    const confirm = c?.isConnected && visible(c) ? c.getBoundingClientRect() : null;
    return generateMenuPlace(
      f.getBoundingClientRect(),
      confirm,
      MENU_WIDTH,
      menuHeight(),
      { width: innerWidth, height: innerHeight },
      isRTL(f),
    ).vertical.above;
  };

  const close = () => {
    asking++;
    clearTimeout(regenTimer);
    dragSession = null;
    setDragging(false);
    setMenuPos(null);
    setMenu(null);
    setCopied(false);
  };

  function scan() {
    setTargets(generateTargets());
    setTick((n) => n + 1);
  }

  const place = (t: Target) => {
    tick();
    if (!t.field.isConnected || !visible(t.field)) return { display: 'none' };
    return iconPosition(t.field.getBoundingClientRect(), isRTL(t.field), innerWidth);
  };

  const fixedAt = (left: string, top: string, width: number) =>
    ({ position: 'fixed' as const, left, top, width: `${width}px`, right: 'auto', bottom: 'auto' });

  /** Fixed viewport place from menuPos (drag commits here); fall back to anchor only if unset. */
  const menuStyle = (m: Menu) => {
    let pos = menuPos() ?? anchorPlace(m);
    if (!pos || !Number.isFinite(pos.left) || !Number.isFinite(pos.top)) {
      // Last resort so a transient NaN/anchor miss does not hide an open menu (and break drag).
      pos = { left: 8, top: 8 };
    }
    // `fixed` + clear right/bottom: same viewport coords as getBoundingClientRect; avoids the
    // absolute-in-0×0-host Safari trap that parked only the X edge wrong under WXT.
    return fixedAt(`${pos.left}px`, `${pos.top}px`, MENU_WIDTH);
  };

  /** Read the card's on-screen left/top, even if menuPos was never seeded (jsdom / Safari edge). */
  function visualPlace(open: Menu): MenuPos {
    const seeded = menuPos();
    if (seeded && Number.isFinite(seeded.left) && Number.isFinite(seeded.top)) return seeded;
    const anchored = anchorPlace(open);
    if (anchored && Number.isFinite(anchored.left) && Number.isFinite(anchored.top)) return anchored;
    if (menuEl) {
      const left = Number.parseFloat(menuEl.style.left);
      const top = Number.parseFloat(menuEl.style.top);
      if (Number.isFinite(left) && Number.isFinite(top)) return { left, top };
    }
    return { left: 8, top: 8 };
  }

  /** Drag from the "Suggested password" header; the place lasts until the menu closes. */
  function onDragHandle(e: PointerEvent) {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    const open = menu();
    if (!open) return;
    const current = visualPlace(open);
    // Ensure we are driving an absolute place before the first move (not a zeroed delta).
    setMenuPos(current);
    dragSession = {
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      origLeft: current.left,
      origTop: current.top,
    };
    setDragging(true);
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {
      // setPointerCapture can throw if the pointer is already gone
    }

    const move = (ev: PointerEvent) => {
      if (!dragSession || ev.pointerId !== dragSession.pointerId) return;
      const next = applyMenuDrag(
        dragSession.origLeft,
        dragSession.origTop,
        ev.clientX - dragSession.startX,
        ev.clientY - dragSession.startY,
        MENU_WIDTH,
        menuHeight(),
        { width: innerWidth, height: innerHeight },
      );
      const abs = { left: Number.parseFloat(next.left), top: Number.parseFloat(next.top) };
      setMenuPos(abs);
      // Write the node directly so a mid-drag Solid re-render cannot flash the pre-drag place.
      if (menuEl) {
        menuEl.style.left = next.left;
        menuEl.style.top = next.top;
      }
    };

    const up = (ev: PointerEvent) => {
      if (dragSession && ev.pointerId !== dragSession.pointerId) return;
      dragSession = null;
      setDragging(false);
      document.removeEventListener('pointermove', move, true);
      document.removeEventListener('pointerup', up, true);
      document.removeEventListener('pointercancel', up, true);
    };

    document.addEventListener('pointermove', move, true);
    document.addEventListener('pointerup', up, true);
    document.addEventListener('pointercancel', up, true);
  }

  function applyReplyOptions(kind: Kind, reply: Awaited<ReturnType<typeof send>>) {
    if (kind === 'password') {
      setPassword({
        length: reply.length ?? password().length,
        uppercase: reply.uppercase ?? password().uppercase,
        lowercase: reply.lowercase ?? password().lowercase,
        digits: reply.digits ?? password().digits,
        symbols: reply.symbols ?? password().symbols,
        avoidAmbiguous: reply.avoidAmbiguous ?? password().avoidAmbiguous,
        minNumbers: reply.minNumbers ?? password().minNumbers,
        minSpecial: reply.minSpecial ?? password().minSpecial,
      });
      setSeededPassword(true);
    } else {
      setPassphrase({
        words: reply.length ?? passphrase().words,
        separator: reply.separator ?? passphrase().separator,
        capitalize: reply.capitalize ?? passphrase().capitalize,
        includeNumber: reply.includeNumber ?? passphrase().includeNumber,
      });
      setSeededPassphrase(true);
    }
  }

  function buildGenerateRequest(kind: Kind): Request {
    const request: Request = {
      command: 'generate',
      field: kind === 'passphrase' ? 'passphrase' : undefined,
    };
    if (kind === 'password' && seededPassword()) {
      const p = password();
      request.length = p.length;
      request.uppercase = p.uppercase;
      request.lowercase = p.lowercase;
      request.digits = p.digits;
      request.symbols = p.symbols;
      request.avoidAmbiguous = p.avoidAmbiguous;
      request.minNumbers = p.minNumbers;
      request.minSpecial = p.minSpecial;
    } else if (kind === 'passphrase' && seededPassphrase()) {
      const p = passphrase();
      request.length = p.words;
      request.separator = p.separator;
      request.capitalize = p.capitalize;
      request.includeNumber = p.includeNumber;
    }
    return request;
  }

  /**
   * Ask the app for a fresh value. `soft` keeps the previous suggestion visible while a new one loads
   * (option tweaks / regenerate) so the dialog does not flash empty "Generating…".
   */
  async function generate(target: Target, kind: Kind, opts: { soft?: boolean } = {}) {
    const mine = ++asking;
    lastKind = kind;
    const prev = menu();
    // Keep the prior suggestion while a soft regen loads — including Password↔Passphrase tab
    // switches — so the panel cross-fades instead of flashing empty "Generating…".
    const keep =
      !!opts.soft &&
      !!prev &&
      prev.target.field === target.field &&
      !!prev.value &&
      !prev.error;
    setMenu({
      target,
      kind,
      value: keep ? prev!.value : undefined,
      entropyBits: keep ? prev!.entropyBits : undefined,
    });
    if (!keep) setCopied(false);
    if (keep) setUpdating(true);
    try {
      const reply = await send(buildGenerateRequest(kind));
      if (mine !== asking) return;
      if (!reply.ok || !reply.value) {
        return setMenu({ target, kind, error: replyErrorMessage(reply) });
      }
      applyReplyOptions(kind, reply);
      setMenu({ target, kind, value: reply.value, entropyBits: reply.entropyBits });
    } finally {
      if (mine === asking) setUpdating(false);
    }
  }

  /** Coalesce rapid option changes (esp. range drag) into one soft regenerate. */
  function scheduleRegen(kind: Kind) {
    clearTimeout(regenTimer);
    regenTimer = window.setTimeout(() => {
      const open = menu();
      if (open) void generate(open.target, kind, { soft: true });
    }, 160);
  }

  function patchPassword(patch: Partial<PasswordOpts>) {
    setPassword((p) => ({ ...p, ...patch }));
    setSeededPassword(true);
    scheduleRegen('password');
  }

  function patchPassphrase(patch: Partial<PassphraseOpts>) {
    setPassphrase((p) => ({ ...p, ...patch }));
    setSeededPassphrase(true);
    scheduleRegen('passphrase');
  }

  const closeWho = () => {
    askingWho++;
    setWho(null);
  };

  async function openWho(target: Target, regen = false) {
    const mine = ++askingWho;
    if (!regen) {
      setWhoActive(-1);
      setWho({ target, emails: [], note: t('gen.lookingForEmails') });
    }
    const reply = await send({ command: 'generate', field: wantsEmail(target.username!) ? 'email' : 'username' });
    if (mine !== askingWho) return;
    const emails = (reply.rows ?? []).map((r) => r.name);
    if (!reply.ok) return setWho({ target, emails: [], note: replyErrorMessage(reply) });
    // An app older than this extension answers with a password (it carries entropyBits): never offer that as a name.
    const outdated = reply.entropyBits != null;
    const value = outdated ? undefined : reply.value;
    setWho({
      target,
      emails,
      value,
      note:
        value || emails.length
          ? undefined
          : outdated
            ? t('gen.updateAppForNames')
            : t('gen.unlockForEmails'),
    });
  }

  function toggleWho(target: Target) {
    if (who()?.target.username === target.username) return closeWho();
    close();
    void openWho(target);
  }

  /** One click, like 1Password: the name, and a strong password while that field is still empty, then offer to save. */
  async function pickWho(w: Who, value: string) {
    setValue(whoField(w), value);
    closeWho();
    if (w.target.field.value) return;
    const mine = askingWho;
    const reply = await send({ command: 'generate' });
    // Another menu opened meanwhile, or the person typed a password: leave it.
    if (mine !== askingWho || !reply.ok || !reply.value || w.target.field.value) return;
    use({ target: w.target, kind: 'password', value: reply.value });
  }

  const whoStyle = (w: Who) => {
    tick();
    const field = whoField(w);
    if (!field.isConnected) return { display: 'none' };
    const r = field.getBoundingClientRect();
    const rows = whoChoices(w).length || 1;
    return fixedAt(menuLeft(r, WHO_WIDTH, isRTL(field), innerWidth), menuVertical(r, rows * 44 + 40, innerHeight).top, WHO_WIDTH);
  };

  function toggle(target: Target) {
    if (menu()?.target.field === target.field) return close();
    closeWho();
    setMenuPos(null);
    void generate(target, lastKind);
  }

  /** Put the shown value in the new password and its confirm field. */
  function use(m: Menu) {
    if (!m.value) return;
    setValue(m.target.field, m.value);
    // The confirm field gets the same value, so the person does not retype a password they never saw.
    if (m.target.confirm?.isConnected && !m.target.confirm.disabled) setValue(m.target.confirm, m.value);
    m.target.field.focus();
    // Offer to save now, like 1Password and Bitwarden. Without a username yet, the submit offers it instead (an empty
    // username here would leave a second, nameless login waiting in the app).
    const username = (m.target.username ?? usernameFor(m.target.field))?.value.trim();
    if (username) void send({ command: 'save', username, password: m.value });
    close();
  }

  async function copyValue(m: Menu) {
    if (!m.value) return;
    try {
      await navigator.clipboard.writeText(m.value);
      setCopied(true);
      clearTimeout(copyTimer);
      copyTimer = window.setTimeout(() => setCopied(false), 1200);
    } catch {
      // Clipboard can be blocked; the Use button still fills the fields.
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
      attributeFilter: ['type', 'style', 'class', 'autocomplete', 'hidden', 'disabled'],
    });
    const outside = (e: MouseEvent) => {
      if (dragging() || dragSession) return; // don't close while dragging
      const host = (root.getRootNode() as ShadowRoot).host;
      if (e.composedPath().includes(host)) return;
      if (menu()) close();
      if (who()) closeWho();
    };
    const keys = (e: KeyboardEvent) => {
      const w = who();
      if (w && e.key === 'Escape') closeWho();
      // Like the vault fill menu: ↑ / ↓ from the field pick a row, Enter takes it.
      else if (w && !w.note && e.target === whoField(w)) {
        const choices = whoChoices(w);
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          e.stopPropagation();
          setWhoActive((i) => (e.key === 'ArrowDown' ? Math.min(i + 1, choices.length - 1) : Math.max(i - 1, 0)));
        } else if (e.key === 'Enter' && choices[whoActive()]) {
          e.preventDefault();
          e.stopPropagation();
          void pickWho(w, choices[whoActive()]!);
        }
      }
      const m = menu();
      if (!m) return;
      if (e.key === 'Escape') close();
      // Enter in the field while the menu shows a value: use it (and don't submit the form half-filled).
      else if (e.key === 'Enter' && m.value && e.target === m.target.field) {
        e.preventDefault();
        e.stopPropagation();
        use(m);
      }
    };
    // A field that appears on focus (step-by-step sign-up) or a form revealed by a class change: look again.
    const focused = (e: FocusEvent) => {
      if (e.target instanceof HTMLInputElement && e.target.type === 'password') rescan();
    };
    document.addEventListener('focusin', focused, true);
    addEventListener('scroll', move, { passive: true, capture: true });
    addEventListener('resize', move, { passive: true });
    document.addEventListener('mousedown', outside, true);
    document.addEventListener('keydown', keys, true);
    onCleanup(() => {
      clearTimeout(timer);
      clearTimeout(copyTimer);
      clearTimeout(regenTimer);
      observer.disconnect();
      removeEventListener('scroll', move, true);
      removeEventListener('resize', move);
      document.removeEventListener('mousedown', outside, true);
      document.removeEventListener('keydown', keys, true);
      document.removeEventListener('focusin', focused, true);
    });
  });

  const refreshIcon = (
    <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true">
      <path
        d="M13.5 8a5.5 5.5 0 1 1-1.61-3.89M13.5 2.5v3.2h-3.2"
        fill="none"
        stroke="currentColor"
        stroke-width="1.6"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  );

  const copyIcon = (done: boolean) =>
    done ? (
      <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true">
        <path
          d="M3.5 8.5 6.5 11.5 12.5 4.5"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    ) : (
      <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true">
        <rect x="5.5" y="5.5" width="7" height="8" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.4" />
        <path
          d="M3.5 10.5V3.8A1.3 1.3 0 0 1 4.8 2.5h5.7"
          fill="none"
          stroke="currentColor"
          stroke-width="1.4"
          stroke-linecap="round"
        />
      </svg>
    );

  return (
    <div ref={root}>
      <For each={targets()}>
        {(target) => (
          <button
            class="key"
            type="button"
            title={t('gen.suggestPassword')}
            aria-label={t('gen.suggestPasswordAria')}
            style={place(target)}
            on:mousedown={(e) => e.preventDefault()}
            on:click={() => toggle(target)}
          >
            <AppMark size={22} />
          </button>
        )}
      </For>
      <For each={targets().filter((x) => x.username)}>
        {(tg) => (
          <button
            class="key"
            type="button"
            title={wantsEmail(tg.username!) ? t('gen.yourEmails') : t('gen.suggestUsername')}
            aria-label={wantsEmail(tg.username!) ? t('gen.chooseEmailAria') : t('gen.suggestUsernameAria')}
            style={place({ field: tg.username! })}
            on:mousedown={(e) => e.preventDefault()}
            on:click={() => toggleWho(tg)}
          >
            <AppMark size={22} />
          </button>
        )}
      </For>
      <Show when={who()}>
        {(w) => {
          const email = () => wantsEmail(whoField(w()));
          const row = (value: string, i: number, detail?: string) => (
            <div
              class="row"
              role="menuitem"
              data-active={i === whoActive()}
              onMouseEnter={() => setWhoActive(i)}
              on:click={() => void pickWho(w(), value)}
            >
              <span class="text">
                <span class="name" dir="auto">
                  {value}
                </span>
                <Show when={detail}>
                  <span class="detail">{detail}</span>
                </Show>
              </span>
            </div>
          );
          return (
            <div
              class="menu"
              role="menu"
              style={whoStyle(w())}
              data-rtl={isRTL(whoField(w()))}
              on:mousedown={(e) => e.preventDefault()}
            >
              <Show
                when={!w().note}
                fallback={
                  <div class="note" dir="auto" role="status" aria-live="polite">
                    {w().note}
                  </div>
                }
              >
                <div class="list">
                  <Show when={w().emails.length}>
                    <div class="group">{t('gen.yourEmails')}</div>
                    <For each={w().emails}>{(address, i) => row(address, i())}</For>
                  </Show>
                  <Show when={w().value}>
                    {(v) => (
                      <>
                        <div class="group">{email() ? t('gen.privateAddress') : t('gen.newUsername')}</div>
                        {/* The refresh button sits beside the row, not inside it: no button within a menu item. */}
                        <div class="who-generated">
                          {row(
                            v(),
                            w().emails.length,
                            email() ? t('gen.privateAddressDetail') : t('gen.newUsernameDetail'),
                          )}
                          <button
                            class="icon-btn"
                            type="button"
                            title={t('gen.anotherOne')}
                            aria-label={t('gen.generateAnother')}
                            on:click={() => void openWho(w().target, true)}
                          >
                            {refreshIcon}
                          </button>
                        </div>
                      </>
                    )}
                  </Show>
                </div>
                <Show when={!w().target.field.value}>
                  <div class="hint">{t('gen.alsoFillsPassword')}</div>
                </Show>
              </Show>
            </div>
          );
        }}
      </Show>
      <Show when={menu()}>
        {(m) => {
          const strength = () => strengthLevel(m().entropyBits ?? 0);
          return (
            <div
              ref={(el) => {
                menuEl = el;
              }}
              class="menu gen"
              role="dialog"
              aria-label={t('gen.suggestedPassword')}
              style={menuStyle(m())}
              data-rtl={isRTL(m().target.field)}
              data-above={menuAbove(m())}
              data-dragging={dragging()}
              on:mousedown={(e) => {
                // Keep focus on the password field when clicking chrome, but do not block
                // native range-thumb drag or caret in inputs (Safari needs mousedown).
                const el = e.target as HTMLElement | null;
                if (el?.closest('input, textarea, select, [data-allow-mouse]')) return;
                e.preventDefault();
              }}
            >
              <div class="group gen-drag" title={t('gen.dragToMove')} on:pointerdown={(e) => onDragHandle(e)}>
                {m().kind === 'passphrase' ? t('gen.suggestedPassphrase') : t('gen.suggestedPassword')}
              </div>

              <div class="gen-kinds" role="radiogroup" aria-label={t('gen.kind')} data-kind={m().kind}>
                <span class="gen-kinds-thumb" aria-hidden="true" />
                <For each={['password', 'passphrase'] as Kind[]}>
                  {(kind) => (
                    <button
                      type="button"
                      role="radio"
                      aria-checked={m().kind === kind}
                      data-on={m().kind === kind}
                      on:click={() => m().kind !== kind && void generate(m().target, kind, { soft: true })}
                    >
                      {kind === 'password' ? t('gen.password') : t('gen.passphrase')}
                    </button>
                  )}
                </For>
              </div>

              <Show when={!m().error} fallback={<div class="note" dir="auto">{m().error}</div>}>
                <div class="gen-output">
                  <div
                    class="row gen-row"
                    role="button"
                    data-active="true"
                    aria-disabled={!m().value}
                    aria-label={m().target.confirm ? t('gen.fillPasswordAndConfirm') : t('gen.fillPassword')}
                    on:click={() => use(m())}
                  >
                    <span class="text">
                      <span class="gen-value" data-loading={!m().value} data-updating={updating()}>
                        <Show when={m().value} fallback={t('gen.generating')}>
                          {(v) => <Pretty value={v()} />}
                        </Show>
                      </span>
                    </span>
                    <button
                      class="icon-btn"
                      type="button"
                      title={t('gen.anotherOne')}
                      aria-label={t('gen.generateAnother')}
                      on:click={(e) => {
                        e.stopPropagation();
                        void generate(m().target, m().kind, { soft: true });
                      }}
                    >
                      {refreshIcon}
                    </button>
                    <button
                      class="icon-btn"
                      type="button"
                      title={copied() ? t('gen.copied') : t('gen.copy')}
                      aria-label={copied() ? t('gen.copied') : t('gen.copy')}
                      disabled={!m().value}
                      on:click={(e) => {
                        e.stopPropagation();
                        void copyValue(m());
                      }}
                    >
                      {copyIcon(copied())}
                    </button>
                  </div>
                  <Show when={m().value && m().entropyBits != null}>
                    <div class="gen-strength" aria-label={t('gen.strength', t(strength().labelKey))}>
                      <div class="gen-strength-bars" data-level={strength().level}>
                        <For each={[1, 2, 3, 4]}>{(i) => <span data-on={i <= strength().level} />}</For>
                      </div>
                      <span class="gen-strength-label">{t(strength().labelKey)}</span>
                    </div>
                  </Show>
                </div>

                <Show when={m().kind === 'password'}>
                  <div class="gen-options gen-tab-pane" data-kind="password">
                    <div class="gen-opt-stack">
                      <span class="gen-opt-label">{t('gen.length')}</span>
                      <div class="gen-opt-row">
                        <input
                          class="gen-slider"
                          type="range"
                          min="5"
                          max="128"
                          value={password().length}
                          aria-label={t('gen.length')}
                          style={{ '--pct': `${((password().length - 5) / (128 - 5)) * 100}%` }}
                          on:pointerdown={(e) => e.stopPropagation()}
                          on:mousedown={(e) => e.stopPropagation()}
                          on:input={(e) => patchPassword({ length: Number((e.currentTarget as HTMLInputElement).value) })}
                          on:click={(e) => e.stopPropagation()}
                        />
                        <Stepper
                          label={t('gen.length')}
                          value={password().length}
                          min={5}
                          max={128}
                          onChange={(n) => patchPassword({ length: n })}
                        />
                      </div>
                    </div>
                    <div class="gen-opt-stack">
                      <span class="gen-opt-label">{t('gen.include')}</span>
                      <div class="gen-chips">
                        <For
                          each={
                            [
                              ['uppercase', 'A-Z'],
                              ['lowercase', 'a-z'],
                              ['digits', '0-9'],
                              ['symbols', '!@#$'],
                            ] as ['uppercase' | 'lowercase' | 'digits' | 'symbols', string][]
                          }
                        >
                          {([key, title]) => (
                            <button
                              type="button"
                              class="gen-chip"
                              data-on={password()[key]}
                              aria-pressed={password()[key]}
                              on:click={(e) => {
                                e.stopPropagation();
                                patchPassword({ [key]: !password()[key] });
                              }}
                            >
                              {title}
                            </button>
                          )}
                        </For>
                      </div>
                    </div>
                    <div class="gen-mins">
                      <div class="gen-min" data-disabled={!password().digits}>
                        <span class="gen-opt-label">{t('gen.minNumbers')}</span>
                        <Stepper
                          label={t('gen.minimumNumbers')}
                          value={password().minNumbers}
                          min={0}
                          max={9}
                          onChange={(n) => password().digits && patchPassword({ minNumbers: n })}
                        />
                      </div>
                      <div class="gen-min" data-disabled={!password().symbols}>
                        <span class="gen-opt-label">{t('gen.minSpecial')}</span>
                        <Stepper
                          label={t('gen.minimumSpecial')}
                          value={password().minSpecial}
                          min={0}
                          max={9}
                          onChange={(n) => password().symbols && patchPassword({ minSpecial: n })}
                        />
                      </div>
                    </div>
                    <div class="gen-switch">
                      <span>{t('gen.avoidAmbiguous')}</span>
                      <button
                        type="button"
                        class="gen-toggle"
                        role="switch"
                        aria-checked={password().avoidAmbiguous}
                        aria-label={t('gen.avoidAmbiguousAria')}
                        data-on={password().avoidAmbiguous}
                        on:click={(e) => {
                          e.stopPropagation();
                          patchPassword({ avoidAmbiguous: !password().avoidAmbiguous });
                        }}
                      />
                    </div>
                  </div>
                </Show>

                <Show when={m().kind === 'passphrase'}>
                  <div class="gen-options gen-tab-pane" data-kind="passphrase">
                    <div class="gen-opt-stack">
                      <span class="gen-opt-label">{t('gen.wordCount')}</span>
                      <div class="gen-opt-row">
                        <input
                          class="gen-slider"
                          type="range"
                          min="3"
                          max="20"
                          value={passphrase().words}
                          aria-label={t('gen.wordCount')}
                          style={{ '--pct': `${((passphrase().words - 3) / (20 - 3)) * 100}%` }}
                          on:pointerdown={(e) => e.stopPropagation()}
                          on:mousedown={(e) => e.stopPropagation()}
                          on:input={(e) => patchPassphrase({ words: Number((e.currentTarget as HTMLInputElement).value) })}
                          on:click={(e) => e.stopPropagation()}
                        />
                        <Stepper
                          label={t('gen.wordCount')}
                          value={passphrase().words}
                          min={3}
                          max={20}
                          onChange={(n) => patchPassphrase({ words: n })}
                        />
                      </div>
                    </div>
                    <div class="gen-opt-row">
                      <span class="gen-opt-label">{t('gen.separator')}</span>
                      <input
                        class="gen-sep"
                        type="text"
                        maxlength={3}
                        value={passphrase().separator}
                        aria-label={t('gen.wordSeparator')}
                        on:input={(e) => {
                          const v = (e.currentTarget as HTMLInputElement).value.slice(0, 3);
                          patchPassphrase({ separator: v });
                        }}
                        on:click={(e) => e.stopPropagation()}
                      />
                    </div>
                    <div class="gen-switch">
                      <span>{t('gen.capitalize')}</span>
                      <button
                        type="button"
                        class="gen-toggle"
                        role="switch"
                        aria-checked={passphrase().capitalize}
                        aria-label={t('gen.capitalize')}
                        data-on={passphrase().capitalize}
                        on:click={(e) => {
                          e.stopPropagation();
                          patchPassphrase({ capitalize: !passphrase().capitalize });
                        }}
                      />
                    </div>
                    <div class="gen-switch">
                      <span>{t('gen.includeNumber')}</span>
                      <button
                        type="button"
                        class="gen-toggle"
                        role="switch"
                        aria-checked={passphrase().includeNumber}
                        aria-label={t('gen.includeNumber')}
                        data-on={passphrase().includeNumber}
                        on:click={(e) => {
                          e.stopPropagation();
                          patchPassphrase({ includeNumber: !passphrase().includeNumber });
                        }}
                      />
                    </div>
                  </div>
                </Show>

                <button
                  class="gen-use"
                  type="button"
                  disabled={!m().value}
                  on:click={() => use(m())}
                >
                  {m().kind === 'passphrase' ? t('gen.usePassphrase') : t('gen.usePassword')}
                </button>
              </Show>
            </div>
          );
        }}
      </Show>
    </div>
  );
}
