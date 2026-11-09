import { createSignal, onCleanup, onMount, Show } from 'solid-js';
import { isGeneratePasswordField, passwordFields, textLike, visible } from '../../lib/dom';
import { bridgeDownMessage, isBridgeDown } from '../../lib/bridge-status';
import { send } from '../../lib/send';

/**
 * Safari-only: ordinary login pages have no generate icon and no vault-fill overlay (system AutoFill
 * owns pick/fill). When the bridge is down, probe on login-field focus and show a page toast so the
 * failure is not silent. Generate fields already surface errors via GenerateOverlay.
 */

const PROBE_COOLDOWN_MS = 20_000;

function isLoginProbeField(el: EventTarget | null): el is HTMLInputElement {
  if (!(el instanceof HTMLInputElement) || !visible(el)) return false;
  if (el.type === 'password') return !isGeneratePasswordField(el);
  return textLike(el) && passwordFields().some((pw) => visible(pw) && !isGeneratePasswordField(pw));
}

export default function BridgeDownBanner() {
  const [note, setNote] = createSignal<string | null>(null);
  let probing = false;
  let lastProbe = 0;
  let dismissedAt = 0;
  let dismissedFor = '';

  async function probe() {
    const now = Date.now();
    if (probing) return;
    if (now - lastProbe < PROBE_COOLDOWN_MS) return;
    probing = true;
    lastProbe = now;
    try {
      const reply = await send({ command: 'match' });
      if (!isBridgeDown(reply)) {
        setNote(null);
        dismissedFor = '';
        return;
      }
      const message = bridgeDownMessage(reply);
      if (dismissedFor === message && now - dismissedAt < PROBE_COOLDOWN_MS * 3) return;
      setNote(message);
    } finally {
      probing = false;
    }
  }

  onMount(() => {
    const onFocus = (e: FocusEvent) => {
      if (isLoginProbeField(e.target)) void probe();
    };
    document.addEventListener('focusin', onFocus, true);
    onCleanup(() => document.removeEventListener('focusin', onFocus, true));
  });

  return (
    <Show when={note()}>
      {(text) => (
        <div class="bridge-banner" role="status" aria-live="polite">
          <div class="bridge-banner-card" dir="auto">
            <span class="bridge-banner-text">{text()}</span>
            <button
              type="button"
              class="bridge-banner-dismiss"
              aria-label="Dismiss"
              on:click={() => {
                dismissedAt = Date.now();
                dismissedFor = text();
                setNote(null);
              }}
            >
              ×
            </button>
          </div>
        </div>
      )}
    </Show>
  );
}
