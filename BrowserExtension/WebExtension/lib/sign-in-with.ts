// "Sign in with Google/Apple/…": remember which provider a site was signed in with, so the vault can offer that
// button again. Nothing secret is read: only the button clicked, the provider page's URL query (which site started
// the flow) and the email of the account row clicked on Google's chooser. The app decides and asks before saving.
//
// Detection is layered (href, then "Sign in with X" text in several languages, then data attributes, then icons inside
// a login-looking context) and ported from icaroharry/oauth-remember-extension (MIT, see THIRD_PARTY_NOTICES.md). The
// provider list is closed: a name that is not one of these never becomes a provider.
import { browser } from 'wxt/browser';
import { send } from './send';

export const PROVIDERS = {
  google: 'Google',
  apple: 'Apple',
  microsoft: 'Microsoft',
  github: 'GitHub',
  facebook: 'Facebook',
  x: 'X',
  amazon: 'Amazon',
  discord: 'Discord',
  slack: 'Slack',
  linkedin: 'LinkedIn',
  gitlab: 'GitLab',
  twitch: 'Twitch',
} as const;
export type Provider = keyof typeof PROVIDERS;
export const isProvider = (id: unknown): id is Provider => typeof id === 'string' && Object.hasOwn(PROVIDERS, id);
/** What the person reads; an id the app sends that we do not know is shown as is. */
export const providerName = (id: string): string => (isProvider(id) ? PROVIDERS[id] : id);

const ALIASES = new Map<string, Provider>([
  ['google', 'google'], ['apple', 'apple'], ['microsoft', 'microsoft'], ['outlook', 'microsoft'], ['live', 'microsoft'],
  ['windows live', 'microsoft'], ['github', 'github'], ['facebook', 'facebook'], ['x', 'x'], ['twitter', 'x'],
  ['amazon', 'amazon'], ['discord', 'discord'], ['slack', 'slack'], ['linkedin', 'linkedin'], ['gitlab', 'gitlab'],
  ['twitch', 'twitch'],
]);

/** Other ways to sign in, never a provider. */
const EXCLUDED = /^(e-?mail|phone|telephone|passkeys?|password|sso|saml|magic[ -]?(link|email)|qr)\b/;

const normalize = (raw: string): string =>
  raw
    .replace(/\s*[([].*?[)\]]\s*/g, ' ') // "Twitter (X)" -> "twitter"
    .toLowerCase()
    .trim()
    .replace(/^(your|sua|su|votre|dein|o|a)\s+/, '')
    .replace(/[^\p{L}\p{N}]+$/u, '') // "Google.", "Google →"
    .trim();

/** A provider's name or alias ("Microsoft account", "Twitter", "Outlook") -> its id; anything else -> null. */
export function providerFromName(raw: string): Provider | null {
  const name = normalize(raw);
  if (!name || EXCLUDED.test(name)) return null;
  // The whole name only: "Apple Pay" and "Google Maps" are not sign-ins.
  return ALIASES.get(name) ?? ALIASES.get(name.replace(/[\s-]*(account|id|konto|アカウント|帐号|帳號|账号|계정)$/, '')) ?? null;
}

/** [host, path (null = any), provider]: addresses that are a provider's sign-in or consent page. */
const RULES: Array<[RegExp, RegExp | null, Provider]> = [
  [/^accounts\.google\.[a-z.]+$/, null, 'google'],
  [/^appleid\.apple\.com$/, /^\/auth\//, 'apple'],
  [/^login\.(microsoftonline|live)\.com$/, null, 'microsoft'],
  [/^github\.com$/, /^\/login\/oauth/, 'github'],
  [/(^|\.)facebook\.com$/, /^\/(v[\d.]+\/)?dialog\//, 'facebook'],
  [/^(www\.)?(x|twitter)\.com$/, /^\/i\/oauth/, 'x'],
  [/^discord\.com$/, /^\/oauth2/, 'discord'],
  [/(^|\.)slack\.com$/, /^\/(openid|oauth)/, 'slack'],
  [/(^|\.)linkedin\.com$/, /^\/oauth/, 'linkedin'],
  [/^gitlab\.com$/, /^\/oauth/, 'gitlab'],
  [/^id\.twitch\.tv$/, null, 'twitch'],
  [/(^|\.)amazon\.com$/, /^\/ap\/(oa|signin)/, 'amazon'],
];

export function providerFromUrl(u: URL): Provider | null {
  if (!/^https?:$/.test(u.protocol)) return null;
  for (const [host, path, id] of RULES) if (host.test(u.hostname) && (!path || path.test(u.pathname))) return id;
  return null;
}

/** Sites the providers themselves run: never the site that started a sign-in. */
const PROVIDER_OWNED =
  /(^|\.)(google\.[a-z.]+|googleapis\.com|apple\.com|microsoftonline\.com|microsoft\.com|live\.com|github\.com|facebook\.com|x\.com|twitter\.com|amazon\.com|discord\.com|slack\.com|linkedin\.com|gitlab\.com|twitch\.tv)$/;

/**
 * On a provider's page: which provider this is and which site started the flow, from the URL query alone. A `continue`
 * that points back into the provider (Google nests them) is searched too. Google's own button frames (/gsi/) are not
 * the flow, so they give nothing.
 */
/** Google's button frames, drawn inside the site: not the flow. Its popup (/gsi/select?origin=…) is, and names the site. */
const GSI_FRAME = /^\/gsi\/(button|iframe)/;

export function idpSite(u: URL, depth = 0): { provider: Provider; site: string } | null {
  const provider = providerFromUrl(u);
  if (!provider || GSI_FRAME.test(u.pathname)) return null;
  for (const key of ['redirect_uri', 'continue', 'origin', 'service']) {
    const value = u.searchParams.get(key);
    let target: URL;
    try {
      target = new URL(value ?? '');
    } catch {
      continue;
    }
    if (!/^https?:$/.test(target.protocol)) continue; // storagerelay:// and friends
    if (!PROVIDER_OWNED.test(target.hostname)) return { provider, site: target.hostname };
    const nested = depth < 2 ? idpSite(target, depth + 1) : null;
    if (nested) return { provider, site: nested.site };
  }
  return null;
}

/** Google's account chooser row: its email, from the row's own attributes, else an address in its text. */
export function extractEmail(row: Element): string | null {
  const own = row.closest('[data-email], [data-identifier]');
  const attr = own?.getAttribute('data-email') || own?.getAttribute('data-identifier');
  const text = (row.textContent ?? '').length <= 300 ? /[\w.+-]+@[\w-]+(\.[\w-]+)+/.exec(row.textContent ?? '')?.[0] : null;
  const email = (attr?.includes('@') ? attr : text)?.trim().toLowerCase();
  return email && email.length <= 254 ? email : null;
}

// --- Button detection ---

const TEXT_PATTERNS = [
  /(?:sign\s*in|log\s*in|login|continue|connect|authenticate)\s+with\s+(.+)/i, // English
  /(?:entrar|entre|continuar|continue|conectar|acessar|acesse|fazer\s*login|fa[cç]a\s*login|iniciar\s*sess[aã]o|inicie\s*sess[aã]o)\s+com\s+(?:o\s+|a\s+|sua\s+conta\s+(?:do\s+|da\s+)?)?(.+)/i, // Portuguese
  /(?:iniciar\s*sesi[oó]n|continuar|conectar|entrar)\s+con\s+(.+)/i, // Spanish
  /(?:se\s+connecter|continuer|connexion)\s+avec\s+(.+)/i, // French
  /(?:anmelden|weiter|fortfahren|einloggen)\s+mit\s+(.+)/i, // German
  /(?:accedi|continua|connetti)\s+con\s+(.+)/i, // Italian
  /(?:inloggen|doorgaan|aanmelden)\s+met\s+(.+)/i, // Dutch
  /(?:ログイン|サインイン|続行)\s*(?:で|を使って)\s*(.+)/i, // Japanese
  /(.+?)\s*(?:で|を使って)\s*(?:ログイン|サインイン|続行|続ける)/i, // Japanese, provider first
  /(?:로그인|계속하기|로그인하기)\s*(.+?)\s*(?:으로|로)\s*$/i, // Korean
  /(?:使用|用)\s*(.+?)\s*(?:登录|登錄|登入|继续|繼續)/i, // Chinese
];

/** Longer text is a container of buttons, not a button. */
const MAX_LABEL = 80;

/** null: the label says "Sign in with <something>" but not a provider; `undefined`: it says no such thing. */
function fromText(el: Element): Provider | null | undefined {
  const labels = [el.textContent, el.getAttribute('aria-label'), (el as HTMLInputElement).value, el.getAttribute('title')];
  for (const label of labels) {
    const raw = typeof label === 'string' ? label.replace(/\s+/g, ' ').trim() : '';
    if (!raw || raw.length > MAX_LABEL) continue;
    for (const re of TEXT_PATTERNS) {
      const name = re.exec(raw)?.[1];
      if (name) return providerFromName(name);
    }
  }
  return undefined;
}

const PATH_PROVIDER = /\/(?:login|auth|oauth2?|signin|connect)\/(\w+)/i;

function fromHref(el: Element): Provider | null {
  const href = el.getAttribute('href');
  if (!href) return null;
  try {
    const u = new URL(href, location.href);
    const id = providerFromUrl(u);
    if (id) return id;
    // Same-site path such as /login/google or /auth/github.
    return u.hostname === location.hostname ? providerFromName(PATH_PROVIDER.exec(u.pathname)?.[1] ?? '') : null;
  } catch {
    return null;
  }
}

const fromAttr = (el: Element): Provider | null =>
  providerFromName(el.getAttribute('data-provider') || el.getAttribute('data-auth-provider') || el.getAttribute('data-social') || '');

/**
 * A button whose whole label is just the provider's name: icon-only with aria-label="google" (AliExpress), or an icon
 * and the word "Google" (Notion). Exact name only.
 */
function fromLabel(el: Element): Provider | null {
  if (!el.matches('button, [role="button"], a[href]')) return null;
  for (const label of [el.getAttribute('aria-label'), el.getAttribute('title'), el.textContent]) {
    const id = label ? ALIASES.get(normalize(label)) : undefined;
    if (id) return id;
  }
  return null;
}

const ICON_NAME = /\b(google|facebook|apple|github|microsoft|twitter|linkedin|discord|slack|twitch|gitlab|amazon)\b/;

/** A pay, maps or music mark that happens to contain a provider's name: not a sign-in icon. */
const NOT_SIGNIN_ICON = /(?:apple|google|amazon)[\s_-]*(?:pay|maps|music|wallet|cash|card)/i;

function fromIcons(el: Element): Provider | null {
  for (const icon of el.querySelectorAll('img, svg')) {
    const hint = `${icon.getAttribute('alt') ?? ''} ${icon.getAttribute('title') ?? ''} ${icon.getAttribute('src') ?? ''}`.toLowerCase();
    if (NOT_SIGNIN_ICON.test(hint)) continue;
    const name = ICON_NAME.exec(hint)?.[1];
    if (name) return providerFromName(name);
  }
  return null;
}

/** Icon-only detection stays inside a login-looking context, so a footer logo or avatar is never a button. */
function inLoginContext(el: Element): boolean {
  const re = /oauth|social|login|log.in|signin|sign.in|auth(?!or)|sso/i;
  for (let node: Element | null = el, i = 0; node && node !== document.body && i < 4; node = node.parentElement, i++) {
    if (typeof node.className === 'string' && re.test(node.className)) return true;
  }
  return false;
}

/** The provider this element signs in with, or null. Layers run from most to least reliable. */
export function detectProvider(el: Element): Provider | null {
  const byHref = fromHref(el);
  if (byHref) return byHref;
  const byText = fromText(el);
  if (byText !== undefined) return byText; // "Sign in with email" must not fall through to an icon
  return fromAttr(el) ?? fromLabel(el) ?? (inLoginContext(el) ? fromIcons(el) : null);
}

const CANDIDATES = [
  'a[href]', 'button', '[role="button"]', 'input[type="submit"]', '[data-provider]', '[data-auth-provider]',
  '[data-social]', '[class*="oauth"]', '[class*="social"]', '[class*="login"]', '[class*="signin"]', '[class*="sso"]',
].join(', ');

/** Words that join "Continue" and a provider's name, in the languages TEXT_PATTERNS reads: a cheap filter before them. */
const JOINER = /\b(with|com|con|avec|mit|met)\b|で|を使って|으로|로|使用|用/i;

/**
 * The element that reads "Continue with Google" when the page drew a button without any button markup (Notion uses
 * plain divs): the highest of the text's three closest ancestors that still reads as only that label.
 */
function labelledBox(text: Text): { el: Element; provider: Provider } | null {
  let best: { el: Element; provider: Provider } | null = null;
  for (let el = text.parentElement, i = 0; el && el !== document.body && i < 3; el = el.parentElement, i++) {
    const provider = fromText(el);
    if (!provider) break;
    best = { el, provider };
  }
  return best;
}

export function findProviderButtons(root: ParentNode = document): Array<{ el: Element; provider: Provider }> {
  const found: Array<{ el: Element; provider: Provider }> = [];
  for (const el of root.querySelectorAll(CANDIDATES)) {
    const provider = detectProvider(el);
    if (provider) found.push({ el, provider });
  }
  // ponytail: walks every text node; the overlay calls this only for a few seconds after load or a click.
  const walker = document.createTreeWalker(root instanceof Document ? root.body ?? root : root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const text = n as Text;
    if (text.data.length > MAX_LABEL || !JOINER.test(text.data)) continue;
    const box = labelledBox(text);
    if (box && !found.some((f) => f.el === box.el || f.el.contains(box.el) || box.el.contains(f.el))) found.push(box);
  }
  // Google's own button is a frame of accounts.google.com: it stands for "Google", though it cannot be pressed from here.
  for (const el of root.querySelectorAll('iframe[src*="accounts.google.com/gsi/button"]')) found.push({ el, provider: 'google' });
  // A wrapper around a detected button is not another button.
  return found.filter((a) => !found.some((b) => b !== a && a.el.contains(b.el)));
}

/**
 * The button under a click: the clicked element or a close ancestor of it that reads as a provider button. Elements
 * without button markup count by their label alone ("Continue with Google" on a plain div).
 */
export function providerAt(target: EventTarget | null): Provider | null {
  if (!(target instanceof Element)) return null;
  for (let el: Element | null = target, i = 0; el && el !== document.body && i < 6; el = el.parentElement, i++) {
    if (el.matches(CANDIDATES)) {
      const provider = detectProvider(el);
      // A control that is not a provider (payment, email, …) must not inherit one from a larger login container.
      if (provider) return provider;
      return null;
    }
    const provider = fromText(el);
    if (provider) return provider;
  }
  return null;
}

// --- One attempt, from the click to coming back (pure: the background keeps the list) ---

/** What is remembered between the click and the return: no secret, kept in session storage only. */
export type Attempt = { site: string; provider: Provider; email?: string; at: number; visited: boolean };

/** An attempt that was never finished is forgotten after this long. */
export const ATTEMPT_MS = 10 * 60_000;

export const live = (list: Attempt[], now: number): Attempt[] => list.filter((a) => now - a.at < ATTEMPT_MS);

/**
 * The registrable domain: the last two labels, or three under a two-letter country code with a short second level
 * (shop.example.co.uk -> example.co.uk, pt.aliexpress.com -> aliexpress.com).
 * ponytail: heuristic, not the Public Suffix List; hosting suffixes (github.io, vercel.app) read as one site. Bundle the
 * PSL if that ever offers to remember a sign-in for the wrong page.
 */
export function baseDomain(host: string): string {
  const labels = host.split('.');
  const n = /^[a-z]{2}$/.test(labels.at(-1) ?? '') && (labels.at(-2)?.length ?? 9) <= 3 ? 3 : 2;
  return labels.slice(-n).join('.');
}

/** The same site: one registrable domain (a provider's callback on thirdparty.example.com, the return on pt.example.com). */
export const sameSite = (a: string, b: string): boolean => a === b || baseDomain(a) === baseDomain(b);

/** The button was clicked on `site`: one attempt per site and provider, started over. */
export function stage(list: Attempt[], site: string, provider: Provider, now: number): Attempt[] {
  return [...live(list, now).filter((a) => !(a.site === site && a.provider === provider)), { site, provider, at: now, visited: false }];
}

/**
 * The provider's page was opened for `site` (and maybe an account picked): a click that went unseen still counts. When
 * the page names no site (GitHub often omits redirect_uri) or another one (a callback on api.example.com for a click on
 * app.example.com), it belongs to the newest click on that provider: the site the person will come back to.
 */
export function visit(list: Attempt[], site: string | undefined, provider: Provider, email: string | undefined, now: number): Attempt[] {
  const kept = live(list, now);
  const clicked = kept.filter((a) => a.provider === provider).sort((a, b) => b.at - a.at)[0];
  const mine = (site ? kept.find((a) => sameSite(a.site, site) && a.provider === provider) : undefined) ?? clicked;
  if (!mine && !site) return kept;
  const next: Attempt = { site: mine?.site ?? site!, provider, email: email ?? mine?.email, at: mine?.at ?? now, visited: true };
  return [...kept.filter((a) => a !== mine), next];
}

/**
 * A page of the site loaded after the click: the provider sent the person back, even when it showed no page of its own
 * (consent given before) and the return was a popup's callback that closed at once (AliExpress). Marked right away,
 * before that popup is gone; the tab the person returns to then shows the card on focus.
 */
export function arrive(list: Attempt[], host: string, now: number): Attempt[] {
  return live(list, now).map((a) => (!a.visited && now - a.at > 1000 && sameSite(a.site, host) ? { ...a, visited: true } : a));
}

/**
 * Back on `host`: the finished attempt for it (newest first) and the list without it. Once per attempt. Finished means
 * the provider's page was seen, or — `fresh`, a page newly loaded after the click — the provider sent the person
 * straight back without showing a page (consent already given: a server redirect no content script sees). A tab merely
 * regaining focus (a popup closed) needs the provider page.
 */
export function take(list: Attempt[], host: string, now: number, fresh = false): [Attempt | undefined, Attempt[]] {
  const kept = live(list, now);
  const hit = kept.filter((a) => (a.visited || fresh) && sameSite(a.site, host)).sort((a, b) => b.at - a.at)[0];
  return [hit, kept.filter((a) => a !== hit)];
}

// --- Content script ---

// A tab opened before the extension was reloaded keeps an orphaned script whose sendMessage throws at once
// ("Extension context invalidated"): nothing to tell then.
const tell = (message: object): Promise<unknown> =>
  Promise.resolve().then(() => browser.runtime.sendMessage(message)).catch(() => null);

let returning = false;
const SETTLE_MS = 2000;

/** Back on the site after the provider: ask the background once; if an attempt finished, offer to remember it. */
async function checkReturn(fresh: boolean): Promise<void> {
  if (returning) return;
  returning = true;
  try {
    const hit = (await tell({ signIn: 'take', fresh })) as { provider?: string; email?: string } | null;
    // The background adds the address (the browser's own); no password: the app asks in its own window before keeping anything.
    if (hit && isProvider(hit.provider)) await send({ command: 'save', provider: hit.provider, username: hit.email ?? '' });
  } finally {
    returning = false;
  }
}

export function watchSignInWith(): void {
  // Google's own button (and One Tap) lives in a cross-origin frame: a click in it is the click on the button.
  if (/^accounts\.google\.[a-z.]+$/.test(location.hostname) && GSI_FRAME.test(location.pathname)) {
    document.addEventListener('click', () => void tell({ signIn: 'stage', provider: 'google' }), true);
    return;
  }
  const idp = providerFromUrl(new URL(location.href));
  if (idp) {
    // The background reads this page's address itself; only the account the person clicked is added.
    void tell({ signIn: 'visit' });
    if (idp === 'google') {
      document.addEventListener(
        'click',
        (e) => {
          const email = e.target instanceof Element ? extractEmail(e.target.closest('[data-email], [data-identifier], li, [role="link"], [role="button"]') ?? e.target) : null;
          if (email) void tell({ signIn: 'visit', email });
        },
        true,
      );
    }
    return;
  }
  // Login modals are often a frame of their own: a click there counts for the page (the background uses the top frame's address).
  document.addEventListener(
    'click',
    (e) => {
      const provider = providerAt(e.target);
      if (provider) void tell({ signIn: 'stage', provider });
    },
    true,
  );
  // Google's own button is a frame of accounts.google.com laid over the site's button (Pinterest): a click in it reaches
  // no script of this page, but this window loses focus to that frame. That focus change is the click.
  addEventListener('blur', () =>
    setTimeout(() => {
      const frame = document.activeElement;
      if (frame instanceof HTMLIFrameElement && /^https:\/\/accounts\.google\.com\/gsi\/button/.test(frame.src)) {
        void tell({ signIn: 'stage', provider: 'google' });
      }
    }),
  );
  if (window !== window.top) return;
  // A provider's callback on the site (thirdparty.example.com/callback) redirects at once: only a page that stays open
  // for a moment is the one the person came back to, so the card shows where they are.
  let settle: ReturnType<typeof setTimeout> | undefined;
  void tell({ signIn: 'arrive' }); // now, not after settling: a popup's callback page closes within a second
  let fresh = true; // the first check is this page's own load
  const check = () => {
    clearTimeout(settle);
    settle = setTimeout(() => {
      void checkReturn(fresh);
      fresh = false;
    }, SETTLE_MS);
  };
  addEventListener('popstate', check);
  addEventListener('hashchange', check);
  addEventListener('focus', check);
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && check());
  check();
}
