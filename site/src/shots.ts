/** Real app screenshots (public/assets/shots/<name>-light|dark.webp), captured with
    `Triwarden --demo-full --shoot -appearance light|dark` — windows with their own shadows, on transparency. */
export const SHOTS = {
  vault: { w: 1800, h: 1388 },
  search: { w: 1800, h: 1388 },
  codes: { w: 1800, h: 1388 },
  watchtower: { w: 1800, h: 1388 },
  palette: { w: 1800, h: 1388 },
  // The palette capture with the window behind it blurred (promo/scripts/focus-palette.py).
  "palette-focus": { w: 1800, h: 1388 },
  generator: { w: 1800, h: 1388 },
  menubar: { w: 852, h: 1616 },
  signin: { w: 1800, h: 1388 },
  locked: { w: 1800, h: 1388 },
  // Local API keys: opaque renders of one pane or panel each (no transparent margin), framed by the page.
  "tw-real": { w: 2080, h: 1584 },
  "tw-ready-detail": { w: 880, h: 1624 },
  "tw-access": { w: 1920, h: 1764 },
  "tw-approval": { w: 1200, h: 1904 },
  "tw-env-import": { w: 1200, h: 1344 },
  "tw-guide-tool": { w: 1280, h: 1344 },
  "tw-notch-expanded": { w: 1240, h: 824 },
  "tw-notch-request": { w: 1240, h: 824 },
} as const;

export type ShotName = keyof typeof SHOTS;
