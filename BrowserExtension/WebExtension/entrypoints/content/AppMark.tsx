/** The Triwarden app icon (Design/AppIcon/AppIcon.svg without the tick marks, which vanish at this size). */
export const AppMark = (props: { size: number }) => (
  <svg viewBox="0 0 1024 1024" width={props.size} height={props.size} aria-hidden="true">
    <defs>
      <linearGradient id="tw-bg" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#8FCDF3" />
        <stop offset="1" stop-color="#4BA7E0" />
      </linearGradient>
      <radialGradient id="tw-hi" cx=".5" cy=".15" r=".75">
        <stop offset="0" stop-color="#FFFFFF" stop-opacity=".28" />
        <stop offset="1" stop-color="#FFFFFF" stop-opacity="0" />
      </radialGradient>
      <linearGradient id="tw-plate" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#FFFFFF" />
        <stop offset=".5" stop-color="#E7EEF4" />
        <stop offset="1" stop-color="#D3DEE8" />
      </linearGradient>
      <linearGradient id="tw-face" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#FFFFFF" />
        <stop offset="1" stop-color="#E4F2FB" />
      </linearGradient>
      <linearGradient id="tw-r1" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#A9DAF7" />
        <stop offset="1" stop-color="#6DBBEB" />
      </linearGradient>
      <linearGradient id="tw-r2" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#4AA8E4" />
        <stop offset="1" stop-color="#2283C9" />
      </linearGradient>
      <linearGradient id="tw-r3" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#1670AE" />
        <stop offset="1" stop-color="#0A4E80" />
      </linearGradient>
    </defs>
    <rect width="1024" height="1024" rx="230" fill="url(#tw-bg)" />
    <rect width="1024" height="1024" rx="230" fill="url(#tw-hi)" />
    <circle cx="512" cy="512" r="404" fill="#E7EEF4" />
    <g transform="translate(512 512) scale(0.8596) translate(-512 -512)">
      <circle cx="512" cy="512" r="470" fill="url(#tw-plate)" />
      <circle cx="512" cy="512" r="344" fill="url(#tw-face)" />
      <path d="M477.0 779.7 A270 270 0 1 1 547.0 779.7" fill="none" stroke-width="40" stroke-linecap="round" stroke="url(#tw-r1)" />
      <path d="M477.0 710.9 A202 202 0 1 1 547.0 710.9" fill="none" stroke-width="40" stroke-linecap="round" stroke="url(#tw-r2)" />
      <path d="M477.0 641.3 A134 134 0 1 1 547.0 641.3" fill="none" stroke-width="40" stroke-linecap="round" stroke="url(#tw-r3)" />
      <circle cx="512" cy="488" r="46" fill="url(#tw-r3)" />
      <path d="M494 500 L530 500 L540 592 Q541 604 529 604 L495 604 Q483 604 484 592 Z" fill="url(#tw-r3)" />
    </g>
  </svg>
);
