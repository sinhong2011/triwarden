// Triwarden content script.
// Safari: generate + save + a bridge-down toast on ordinary login fields (system AutoFill owns vault pick/fill).
// Chrome / Firefox / Edge: vault suggestions/fill overlay + save.
import { render } from 'solid-js/web';
import { pinOverlayHost } from '../../lib/overlay-layout';
import { vaultFillInOverlay } from '../../lib/runtime';
import { watchForSubmits } from '../../lib/save';
import BridgeDownBanner from './BridgeDownBanner';
import GenerateOverlay from './GenerateOverlay';
import Overlay from './Overlay';
import './overlay.css';

export default defineContentScript({
  matches: ['https://*/*', 'http://*/*'],
  allFrames: true,
  runAt: 'document_idle',
  // The overlay lives in a closed shadow root, so page styles can't touch it and ours don't leak out.
  cssInjectionMode: 'ui',

  async main(ctx) {
    watchForSubmits();
    const ui = await createShadowRootUi(ctx, {
      name: 'triwarden-overlay',
      position: 'overlay',
      zIndex: 2147483647,
      // String selector (not Element) so autoMount can watch for body appearing / being replaced.
      anchor: 'body',
      mode: 'closed',
      onMount: (container) => {
        const dispose = render(
          () =>
            vaultFillInOverlay() ? (
              <Overlay />
            ) : (
              <>
                <GenerateOverlay />
                <BridgeDownBanner />
              </>
            ),
          container,
        );
        // After WXT's applyPosition: force a viewport-sized host so Safari places absolute menus on
        // the field. Pin on every mount/remount (autoMount), not only once after createShadowRootUi.
        const root = container.getRootNode();
        const host = root instanceof ShadowRoot ? (root.host as HTMLElement) : null;
        if (host) pinOverlayHost(host, container);
        return dispose;
      },
      onRemove: (dispose) => dispose?.(),
    });
    // One-shot mount() throws when body is missing at idle, and never remounts after SPA body swaps
    // (#182). autoMount waits for the anchor and remounts when it is removed/re-added.
    ui.autoMount();
  },
});
