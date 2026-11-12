type Box = Pick<DOMRect, 'left' | 'right' | 'top' | 'height'>;

/**
 * Horizontal room left clear of Safari / Chrome's native AutoFill key decoration.
 * Geometric only — we do not observe the native icon (fragile across OS / browser builds).
 * Native control is ~20–24px at the trailing edge; 28px leaves a small gap beside our 22px mark.
 * Used only when the viewport has no room to keep the icon outside the field.
 */
export const SYSTEM_AUTOFILL_ICON_CLEARANCE = 28;

const ICON_SIZE = 22;
/** Space between the field's border box and an icon sitting just outside it. Same gap one-time-code rows already used. */
const ICON_OUTSIDE_GAP = 6;
const VIEWPORT_MARGIN = 8;

/**
 * Place the field icon just outside the trailing edge of the box — to the right in left-to-right
 * fields, to the left in right-to-left fields — so it never covers the value or the browser's own
 * trailing decoration. Every overlay icon (fill, generate, one-time code, and any other) uses this.
 *
 * `viewportWidth` keeps the icon on screen. The outside gap shrinks before the icon is allowed to
 * overlap the field. When the field itself runs into the viewport edge, the icon sits clear of the
 * native AutoFill control instead of stacking on it.
 */
export function iconPosition(box: Box, rtl: boolean, viewportWidth = Number.POSITIVE_INFINITY) {
  const preferred = rtl ? box.left - ICON_SIZE - ICON_OUTSIDE_GAP : box.right + ICON_OUTSIDE_GAP;
  const left = clampIconLeft(preferred, box, rtl, viewportWidth);
  return { display: 'grid', left: `${left}px`, top: `${box.top + (box.height - ICON_SIZE) / 2}px` };
}

function clamp(value: number, min: number, max: number) {
  // A viewport narrower than the icon plus margins cannot satisfy both edges. Keep the start margin.
  if (max < min) return min;
  return Math.max(min, Math.min(value, max));
}

function clampIconLeft(preferred: number, box: Box, rtl: boolean, viewportWidth: number) {
  if (!Number.isFinite(viewportWidth)) return preferred;
  const maxLeft = viewportWidth - ICON_SIZE - VIEWPORT_MARGIN;

  if (rtl) {
    if (preferred < VIEWPORT_MARGIN) {
      // Still outside the field when the viewport margin clears its trailing (left) edge.
      if (VIEWPORT_MARGIN + ICON_SIZE <= box.left && VIEWPORT_MARGIN <= maxLeft) return VIEWPORT_MARGIN;
      return clamp(box.left + SYSTEM_AUTOFILL_ICON_CLEARANCE, VIEWPORT_MARGIN, maxLeft);
    }
    if (preferred > maxLeft) return clamp(preferred, VIEWPORT_MARGIN, maxLeft);
    return preferred;
  }

  if (preferred > maxLeft) {
    // Still outside the field when the viewport margin clears its trailing (right) edge.
    if (maxLeft >= box.right && maxLeft >= VIEWPORT_MARGIN) return maxLeft;
    const clearOfDecoration = box.right - SYSTEM_AUTOFILL_ICON_CLEARANCE - ICON_SIZE;
    return clamp(clearOfDecoration, VIEWPORT_MARGIN, maxLeft);
  }
  if (preferred < VIEWPORT_MARGIN) return clamp(preferred, VIEWPORT_MARGIN, maxLeft);
  return preferred;
}

/** Align the menu with the field's writing start while keeping it inside the viewport. */
export function menuLeft(box: Pick<Box, 'left' | 'right'>, width: number, rtl: boolean, viewportWidth: number) {
  const start = rtl ? box.right - width : box.left;
  return `${Math.max(8, Math.min(start, viewportWidth - width - 8))}px`;
}

/**
 * Horizontal place for a menu that belongs to the field icon: the menu's trailing edge meets the
 * icon's trailing edge (LTR ends at the icon; RTL starts at it), so it reads as that icon's panel.
 */
export function menuLeftNearIcon(
  iconLeft: number,
  width: number,
  rtl: boolean,
  viewportWidth: number,
  iconSize = ICON_SIZE,
) {
  const start = rtl ? iconLeft : iconLeft + iconSize - width;
  return `${Math.max(8, Math.min(start, viewportWidth - width - 8))}px`;
}

export type MenuVertical = {
  /** CSS `top` from the viewport. Always set — never `bottom`. */
  top: string;
  /** For spring transform-origin: menus above grow upward. */
  above: boolean;
};

/**
 * Prefer above the field: Safari / Chrome system AutoFill panels claim the space directly under
 * username and password fields, and page / shadow UI cannot cover them. Fall back to below only
 * when there is not enough room above.
 *
 * Always returns `top` (viewport px). CSS `bottom` mis-resolves in Safari's WXT overlay host
 * and parks the menu at the host origin (viewport top-left).
 */
export function menuVertical(
  box: Pick<DOMRect, 'top' | 'bottom'>,
  height: number,
  viewportHeight: number,
  gap = 6,
): MenuVertical {
  const aboveRoom = box.top - 12;
  const belowRoom = viewportHeight - box.bottom - 12;
  if (aboveRoom >= height || aboveRoom >= belowRoom) {
    return { top: `${Math.max(8, box.top - gap - height)}px`, above: true };
  }
  return { top: `${box.bottom + gap}px`, above: false };
}

type Rect = Pick<DOMRect, 'left' | 'right' | 'top' | 'bottom'>;

/**
 * Vertical place for the Safari generate menu: above the new-password field when it fits (system
 * AutoFill owns the strip under the field); otherwise below the confirm field (or the new password
 * when there is none) so the confirm stays readable. Always `top`, never CSS `bottom`.
 */
export function menuVerticalGenerate(
  field: Rect,
  confirm: Rect | null | undefined,
  height: number,
  viewportHeight: number,
  gap = 6,
): MenuVertical {
  const topEdge = Math.min(field.top, confirm?.top ?? Infinity);
  const bottomEdge = Math.max(field.bottom, confirm?.bottom ?? -Infinity);
  const aboveRoom = topEdge - 12;
  const belowRoom = viewportHeight - bottomEdge - 12;
  if (aboveRoom >= height || aboveRoom >= belowRoom) {
    return { top: `${Math.max(8, topEdge - gap - height)}px`, above: true };
  }
  return { top: `${bottomEdge + gap}px`, above: false };
}

/**
 * The generate menu (Safari): tied to the new-password field's icon, and never over the confirm
 * field. Horizontally it ends at the icon (`menuLeftNearIcon`), using the same outside place as
 * the icon itself. Vertically: above the new password when it fits; otherwise below the confirm
 * (or the new password when there is none).
 */
export function generateMenuPlace(
  field: Rect,
  confirm: Rect | null | undefined,
  width: number,
  height: number,
  viewport: { width: number; height: number },
  rtl: boolean,
  gap = 6,
): { left: string; vertical: MenuVertical } {
  const iconLeft = Number.parseFloat(
    iconPosition({ ...field, height: field.bottom - field.top }, rtl, viewport.width).left,
  );
  return {
    left: menuLeftNearIcon(iconLeft, width, rtl, viewport.width),
    vertical: menuVerticalGenerate(field, confirm, height, viewport.height, gap),
  };
}


/** Shift a menu by a drag offset and keep it inside the viewport. */
export function applyMenuDrag(
  baseLeft: number,
  baseTop: number,
  dx: number,
  dy: number,
  width: number,
  height: number,
  viewport: { width: number; height: number },
): { left: string; top: string } {
  const left = Math.max(8, Math.min(baseLeft + dx, viewport.width - width - 8));
  const top = Math.max(8, Math.min(baseTop + dy, viewport.height - height - 8));
  return { left: `${left}px`, top: `${top}px` };
}

/**
 * WXT's `position: 'overlay'` sets the shadow host to `position:relative; width:0; height:0`
 * and injects `:host { all: initial !important }`, which beats those inline styles. Safari then
 * resolves `position: fixed` children against that 0×0 host (or a transformed page ancestor) and
 * parks menus at the viewport origin. Pin the host (and its mount container) to the viewport so
 * absolute/fixed children with getBoundingClientRect coordinates land on the field.
 */
export function pinOverlayHost(host: HTMLElement, container?: HTMLElement | null) {
  const hostPin: Record<string, string> = {
    position: 'fixed',
    top: '0',
    left: '0',
    right: '0',
    bottom: '0',
    width: 'auto',
    height: 'auto',
    margin: '0',
    padding: '0',
    border: 'none',
    overflow: 'visible',
    display: 'block',
    transform: 'none',
    filter: 'none',
    'pointer-events': 'none',
    'z-index': '2147483647',
  };
  for (const [key, value] of Object.entries(hostPin)) {
    host.style.setProperty(key, value, 'important');
  }
  if (!container) return;
  const boxPin: Record<string, string> = {
    position: 'absolute',
    top: '0',
    left: '0',
    right: '0',
    bottom: '0',
    width: 'auto',
    height: 'auto',
    overflow: 'visible',
    'pointer-events': 'none',
  };
  for (const [key, value] of Object.entries(boxPin)) {
    container.style.setProperty(key, value, 'important');
  }
}

/**
 * Put the overlay host in the browser's top layer (`popover="manual"`), above every page stacking context, so no
 * page `z-index` (a focused Bootstrap field, a sticky header) can cover the icon. Where the Popover API is missing,
 * the host's max `z-index` still applies. The top layer is ordered by when each element entered it, so when the page
 * puts something there later (a popover, a modal `<dialog>`, fullscreen) the host is raised again. Returns a cleanup.
 */
export function pinToTopLayer(host: HTMLElement): () => void {
  if (typeof host.showPopover !== 'function') return () => {};
  host.setAttribute('popover', 'manual');
  const raise = () => {
    try {
      if (host.matches(':popover-open')) host.hidePopover();
      host.showPopover();
    } catch {
      // the page changed the attribute or detached the host; the next mount pins it again
    }
  };
  let queued = false;
  const queue = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      raise();
    });
  };
  // A toggle from the host itself (our own raise) must not trigger another raise.
  const onToggle = (e: Event) => {
    if (e.target !== host && (e as ToggleEvent).newState === 'open') queue();
  };
  // `<dialog>.showModal()` does not fire `toggle` in every engine: watch the `open` attribute too.
  const dialogs = new MutationObserver((records) => {
    if (records.some((r) => (r.target as Element).localName === 'dialog' && (r.target as Element).hasAttribute('open'))) {
      queue();
    }
  });
  raise();
  document.addEventListener('toggle', onToggle, true);
  document.addEventListener('fullscreenchange', queue);
  dialogs.observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['open'] });
  return () => {
    document.removeEventListener('toggle', onToggle, true);
    document.removeEventListener('fullscreenchange', queue);
    dialogs.disconnect();
  };
}
