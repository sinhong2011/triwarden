// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest';

vi.mock('wxt/browser', () => ({ browser: { runtime: { sendMessage: vi.fn(async () => null) } } }));
vi.mock('./send', () => ({ send: vi.fn(async () => ({ ok: true })) }));
const { arrive, ATTEMPT_MS, detectProvider, extractEmail, findProviderButtons, idpSite, providerFromName, providerFromUrl, providerAt, sameSite, stage, take, visit } =
  await import('./sign-in-with');

const el = (html: string): Element => {
  document.body.innerHTML = html;
  return document.body.firstElementChild!;
};

describe('closed provider list', () => {
  it('maps aliases and rejects anything else', () => {
    expect(providerFromName('Twitter (X)')).toBe('x');
    expect(providerFromName('Microsoft account')).toBe('microsoft');
    expect(providerFromName('Outlook')).toBe('microsoft');
    expect(providerFromName('your Google Account')).toBe('google');
    expect(providerFromName('Apple ID')).toBe('apple');
    expect(providerFromName('Apple Pay')).toBeNull();
    expect(providerFromName('Google Maps')).toBeNull();
    expect(providerFromName('Google →')).toBe('google');
    expect(providerFromName('Google帐号')).toBe('google');
    expect(providerFromUrl(new URL('https://appleid.apple.com/account/manage'))).toBeNull();
    expect(providerFromName('Spotify')).toBeNull();
    expect(providerFromName('Bitbucket')).toBeNull();
    expect(providerFromName('constructor')).toBeNull();
    expect(providerFromName('')).toBeNull();
  });

  it('knows the providers by address', () => {
    const id = (u: string) => providerFromUrl(new URL(u));
    expect(id('https://accounts.google.com/o/oauth2/v2/auth')).toBe('google');
    expect(id('https://appleid.apple.com/auth/authorize')).toBe('apple');
    expect(id('https://login.microsoftonline.com/common/oauth2/authorize')).toBe('microsoft');
    expect(id('https://login.live.com/oauth20_authorize.srf')).toBe('microsoft');
    expect(id('https://github.com/login/oauth/authorize')).toBe('github');
    expect(id('https://github.com/pricing')).toBeNull();
    expect(id('https://www.facebook.com/v18.0/dialog/oauth')).toBe('facebook');
    expect(id('https://x.com/i/oauth2/authorize')).toBe('x');
    expect(id('https://twitter.com/i/oauth2/authorize')).toBe('x');
    expect(id('https://discord.com/oauth2/authorize')).toBe('discord');
    expect(id('https://slack.com/openid/connect/authorize')).toBe('slack');
    expect(id('https://www.linkedin.com/oauth/v2/authorization')).toBe('linkedin');
    expect(id('https://gitlab.com/oauth/authorize')).toBe('gitlab');
    expect(id('https://id.twitch.tv/oauth2/authorize')).toBe('twitch');
    expect(id('https://evil.example/oauth/authorize')).toBeNull();
  });
});

describe('button detection layers', () => {
  it('reads Brazilian imperatives too (Coursera: "Continue com o Google")', () => {
    expect(detectProvider(el('<button>Continue com o Google</button>'))).toBe('google');
    expect(detectProvider(el('<button>Entre com a Apple</button>'))).toBe('apple');
    expect(detectProvider(el('<button>Faça login com sua conta da Microsoft</button>'))).toBe('microsoft');
  });

  it('finds a plain-div button by its label, and Google\'s own iframe button (Notion, Dropbox)', () => {
    document.body.innerHTML =
      '<div class="x"><div class="y"><svg></svg><div>Continue with Google</div></div></div>' +
      '<div class="footer">Read our story, built with care by people with taste and more words than a button has</div>' +
      '<iframe src="https://accounts.google.com/gsi/button?x=1"></iframe>';
    const found = findProviderButtons();
    expect(found.map((f) => [f.el.tagName, f.provider])).toEqual([['DIV', 'google'], ['IFRAME', 'google']]);
    expect(providerAt(document.querySelector('svg'))).toBe('google');
  });

  it('reads an icon-only button labelled with just the provider name, and nothing looser', () => {
    document.body.innerHTML = '<button aria-label="google"><a></a></button><button aria-label="Google Maps"></button><div aria-label="apple"></div>';
    const [google, maps, div] = [...document.body.children];
    expect(detectProvider(google!)).toBe('google');
    expect(detectProvider(el('<div role="button" tabindex="0"><svg></svg><div>Google</div></div>'))).toBe('google'); // Notion
    expect(detectProvider(maps!)).toBeNull();
    expect(detectProvider(div!)).toBeNull();
  });

  it('href', () => {
    expect(detectProvider(el('<a href="https://accounts.google.com/o/oauth2/auth?x=1">Go</a>'))).toBe('google');
    expect(detectProvider(el('<a href="/login/github">Go</a>'))).toBe('github');
    expect(detectProvider(el('<a href="/login/email">Go</a>'))).toBeNull();
    expect(detectProvider(el('<a href="https://unknown.example/oauth/authorize">Go</a>'))).toBeNull();
  });

  it('text, including Portuguese and other languages', () => {
    expect(detectProvider(el('<button>Sign in with Google</button>'))).toBe('google');
    expect(detectProvider(el('<button>Continue with Apple</button>'))).toBe('apple');
    expect(detectProvider(el('<button>Entrar com o Google</button>'))).toBe('google');
    expect(detectProvider(el('<button>Continuar com a Microsoft</button>'))).toBe('microsoft');
    expect(detectProvider(el('<button>Iniciar sesión con GitHub</button>'))).toBe('github');
    expect(detectProvider(el('<button>Se connecter avec Facebook</button>'))).toBe('facebook');
    expect(detectProvider(el('<button>Googleでログイン</button>'))).toBe('google');
    expect(detectProvider(el('<button aria-label="Log in with Twitter"></button>'))).toBe('x');
  });

  it('data attributes', () => {
    expect(detectProvider(el('<div data-provider="Discord"></div>'))).toBe('discord');
    expect(detectProvider(el('<div data-auth-provider="myspace"></div>'))).toBeNull();
  });

  it('icons only inside a login-looking context', () => {
    expect(detectProvider(el('<div class="social-login"><button><img alt="Google logo"></button></div>').firstElementChild!)).toBe('google');
    expect(detectProvider(el('<div class="footer"><button><img alt="Google logo"></button></div>').firstElementChild!)).toBeNull();
  });

  it('never treats other ways to sign in as a provider', () => {
    for (const label of ['Sign in with email', 'Continue with Passkey', 'Log in with password', 'Sign in with magic link', 'Continue with phone', 'Entrar com e-mail']) {
      expect(detectProvider(el(`<button>${label}</button>`))).toBeNull();
    }
    // The icon of a provider next to "with email" does not make it one.
    expect(detectProvider(el('<div class="login"><button>Sign in with email<img alt="google"></button></div>').firstElementChild!)).toBeNull();
  });

  it('finds buttons on a page and the one under a click', () => {
    document.body.innerHTML = '<div class="login"><button id=g>Sign in with Google</button><button id=a>Sign in with Apple</button><button>Sign in with email</button></div>';
    expect(findProviderButtons().map((b) => b.provider)).toEqual(['google', 'apple']);
    expect(providerAt(document.querySelector('#a'))).toBe('apple');
    expect(providerAt(document.body)).toBeNull();
  });

  it('does not treat Apple Pay, Google Pay or Amazon Pay icons as sign-ins, even in a login container', () => {
    const applePay = '<img alt="Apple Pay" src="https://cdn.example/apple-pay.svg">';
    const loginButton = (html: string) => el(`<div class="login">${html}</div>`).firstElementChild!;
    expect(detectProvider(loginButton(`<button>Buy with Apple Pay${applePay}</button>`))).toBeNull();
    expect(detectProvider(loginButton(`<button>Check out with Apple Pay${applePay}</button>`))).toBeNull();
    expect(detectProvider(loginButton(`<button>Continue with Apple Pay${applePay}</button>`))).toBeNull();
    expect(providerAt(loginButton(`<button id="cont">Continue with Apple Pay${applePay}</button>`))).toBeNull();
    expect(providerAt(loginButton(`<button>Buy with Apple Pay${applePay}</button>`).querySelector('img'))).toBeNull();

    document.body.innerHTML =
      '<section class="login">' +
      '<button id="g">Continue with Google</button>' +
      `<button id="buy">Buy with Apple Pay${applePay}</button>` +
      `<button id="cont">Continue with Apple Pay${applePay}</button>` +
      '<button id="gp">Continue with Google Pay<img alt="Google Pay" src="/google-pay.svg"></button>' +
      '<button id="az">Continue with Amazon Pay<img alt="Amazon Pay" src="/amazon-pay.png"></button>' +
      '<button id="maps"><img alt="Google Maps" src="/maps.svg"></button>' +
      '</section>';
    expect(findProviderButtons().map((b) => [(b.el as HTMLElement).id, b.provider])).toEqual([['g', 'google']]);
    expect(providerAt(document.querySelector('#buy'))).toBeNull();
    expect(providerAt(document.querySelector('#cont'))).toBeNull();
    expect(providerAt(document.querySelector('#gp'))).toBeNull();
    expect(providerAt(document.querySelector('#az'))).toBeNull();
    expect(providerAt(document.querySelector('#maps'))).toBeNull();
    expect(providerAt(document.querySelector('#g'))).toBe('google');

    // A real sign-in mark still counts; a maps or pay file name does not.
    expect(detectProvider(el('<div class="social-login"><button><img alt="Apple logo" src="/apple.svg"></button></div>').firstElementChild!)).toBe('apple');
    expect(detectProvider(el('<div class="social-login"><button><img alt="GitHub" src="/github.svg"></button></div>').firstElementChild!)).toBe('github');
    expect(detectProvider(el('<div class="login"><button><img alt="" src="/icons/apple-pay.svg"></button></div>').firstElementChild!)).toBeNull();
  });
});

describe('which site started the flow', () => {
  it("reads Google's popup (/gsi/select?origin=…), not its button frame", () => {
    expect(idpSite(new URL('https://accounts.google.com/gsi/select?client_id=1&ux_mode=popup&origin=https://www.pinterest.com'))).toEqual({ provider: 'google', site: 'www.pinterest.com' });
    expect(idpSite(new URL('https://accounts.google.com/gsi/button?origin=https://www.pinterest.com'))).toBeNull();
  });

  const site = (u: string) => idpSite(new URL(u));
  it('Google redirect_uri, continue and origin', () => {
    expect(site('https://accounts.google.com/o/oauth2/v2/auth?redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb&client_id=1')).toEqual({ provider: 'google', site: 'app.example.com' });
    expect(site('https://accounts.google.com/o/oauth2/auth?origin=https%3A%2F%2Fshop.example.org&redirect_uri=storagerelay%3A%2F%2Fhttps%2Fshop.example.org%3Fid%3D1')).toEqual({ provider: 'google', site: 'shop.example.org' });
    expect(site('https://accounts.google.com/v3/signin/accountchooser?continue=https%3A%2F%2Faccounts.google.com%2Fsignin%2Foauth%3Fredirect_uri%3Dhttps%253A%252F%252Fnested.example.com%252Fcb')).toEqual({ provider: 'google', site: 'nested.example.com' });
  });
  it('Apple, Microsoft, GitHub', () => {
    expect(site('https://appleid.apple.com/auth/authorize?redirect_uri=https%3A%2F%2Fexample.net%2Fapple')).toEqual({ provider: 'apple', site: 'example.net' });
    expect(site('https://login.microsoftonline.com/common/oauth2/v2.0/authorize?redirect_uri=https%3A%2F%2Fwork.example.com%2Fsignin-oidc')).toEqual({ provider: 'microsoft', site: 'work.example.com' });
    expect(site('https://github.com/login/oauth/authorize?redirect_uri=https%3A%2F%2Fci.example.dev%2Fcb')).toEqual({ provider: 'github', site: 'ci.example.dev' });
  });
  it('nothing for pointless, provider-owned or button-frame addresses', () => {
    expect(site('https://github.com/login/oauth/authorize?client_id=1')).toBeNull();
    expect(site('https://accounts.google.com/o/oauth2/auth?continue=https%3A%2F%2Fmyaccount.google.com%2F')).toBeNull();
    expect(site('https://accounts.google.com/gsi/button?origin=https%3A%2F%2Fexample.com')).toBeNull();
    expect(site('https://example.com/?redirect_uri=https%3A%2F%2Fexample.com')).toBeNull();
  });
});

describe('chooser email', () => {
  it('reads the row, only the row', () => {
    expect(extractEmail(el('<div data-email="Ana@Example.com"><span>Ana</span></div>').firstElementChild!)).toBe('ana@example.com');
    expect(extractEmail(el('<div><div data-identifier="bob@example.com"><b>Bob</b></div></div>').firstElementChild!.firstElementChild!)).toBe('bob@example.com');
    expect(extractEmail(el('<li role="link">Carla <small>carla+x@mail.example.org</small></li>'))).toBe('carla+x@mail.example.org');
    expect(extractEmail(el('<li>No address here</li>'))).toBeNull();
    expect(extractEmail(el(`<li>${'x'.repeat(400)} a@b.co</li>`))).toBeNull(); // a whole page's text is not a row
  });
});

describe('attempts', () => {
  const t0 = 1_000_000;
  it('treats subdomains and parents as the same site', () => {
    expect(sameSite('example.com', 'login.example.com')).toBe(true);
    expect(sameSite('login.example.com', 'example.com')).toBe(true);
    expect(sameSite('example.com', 'notexample.com')).toBe(false);
    expect(sameSite('thirdparty.aliexpress.com', 'pt.aliexpress.com')).toBe(true); // sibling callback host
    expect(sameSite('shop.example.co.uk', 'example.co.uk')).toBe(true);
    expect(sameSite('a.co.uk', 'b.co.uk')).toBe(false);
  });

  it('is taken once, and only after the provider page', () => {
    let list = stage([], 'example.com', 'google', t0);
    expect(take(list, 'example.com', t0 + 1)[0]).toBeUndefined(); // abandoned: never went through the provider
    list = visit(list, 'example.com', 'google', 'a@b.co', t0 + 2);
    const [hit, rest] = take(list, 'www.example.com', t0 + 3);
    expect(hit).toMatchObject({ provider: 'google', email: 'a@b.co' });
    expect(take(rest, 'example.com', t0 + 4)[0]).toBeUndefined(); // once per attempt
  });

  it('counts a provider visit even when the click was not seen, and keeps an earlier email', () => {
    let list = visit([], 'example.com', 'apple', 'me@icloud.com', t0);
    list = visit(list, 'example.com', 'apple', undefined, t0 + 1);
    expect(take(list, 'example.com', t0 + 2)[0]).toMatchObject({ provider: 'apple', email: 'me@icloud.com' });
  });

  it('expires after ten minutes and ignores other sites', () => {
    const list = visit(stage([], 'example.com', 'github', t0), 'example.com', 'github', undefined, t0 + 1);
    expect(take(list, 'other.com', t0 + 2)[0]).toBeUndefined();
    expect(take(list, 'example.com', t0 + ATTEMPT_MS)[0]).toBeUndefined();
    expect(stage(list, 'a.com', 'x', t0 + ATTEMPT_MS)).toHaveLength(1); // the stale one is dropped on the next write
  });

  it('ties a provider page with no site, or a sibling callback host, to the newest click on that provider', () => {
    const clicked = stage([], 'app.example.com', 'github', t0);
    expect(take(visit(clicked, undefined, 'github', undefined, t0 + 1), 'app.example.com', t0 + 2)[0]).toMatchObject({ provider: 'github' });
    expect(take(visit(clicked, 'api.example.com', 'github', undefined, t0 + 1), 'app.example.com', t0 + 2)[0]).toMatchObject({ provider: 'github' });
    expect(visit([], undefined, 'github', undefined, t0)).toHaveLength(0); // no click and no site: nothing to remember
  });

  it('a page newly loaded after the click counts (consent given before: no provider page), a refocus does not', () => {
    const clicked = stage([], 'www.vinted.pt', 'google', t0);
    expect(take(clicked, 'www.vinted.pt', t0 + 3000)[0]).toBeUndefined();
    expect(take(clicked, 'www.vinted.pt', t0 + 3000, true)[0]).toMatchObject({ provider: 'google' });
  });

  it('a callback page of the site (a popup that closes at once) finishes the attempt for the tab that regains focus', () => {
    const clicked = stage([], 'pt.aliexpress.com', 'google', t0);
    expect(arrive(clicked, 'thirdparty.aliexpress.com', t0 + 500)[0]!.visited).toBe(false); // the click's own page, not a return
    const back = arrive(clicked, 'thirdparty.aliexpress.com', t0 + 3000);
    expect(take(back, 'pt.aliexpress.com', t0 + 4000)[0]).toMatchObject({ provider: 'google' });
    expect(arrive(clicked, 'other.com', t0 + 3000)[0]!.visited).toBe(false);
  });

  it('restarting a click resets it', () => {
    const list = stage(visit([], 'example.com', 'google', 'a@b.co', t0), 'example.com', 'google', t0 + 5);
    expect(list).toHaveLength(1);
    expect(take(list, 'example.com', t0 + 6)[0]).toBeUndefined();
  });
});
