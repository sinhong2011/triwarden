import { browser } from 'wxt/browser';
import en from '../locales/en.json';

/** Nested locale JSON → Chrome `messages.json` keys (`a.b` → `a_b`). */
type Nested = { [key: string]: string | Nested };

function flatten(obj: Nested, prefix = ''): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(obj)) {
    const path = prefix ? `${prefix}_${key}` : key;
    if (typeof value === 'string') out[path] = value;
    else Object.assign(out, flatten(value, path));
  }
  return out;
}

/** English catalog — used when `browser.i18n` is missing (Vitest) or a key is absent. */
const FALLBACK = flatten(en as Nested);

function chromeKey(key: string): string {
  return key.replaceAll('.', '_');
}

/**
 * Translate for the browser UI language (`browser.i18n`). No in-extension language picker.
 * Source of truth: `locales/en.json`; other locales ship via `@wxt-dev/i18n` → `_locales/`.
 *
 * Chrome locale folders: `en`, `zh_TW` (zh-Hant), `zh_CN` (zh-Hans), `ja`.
 */
export function t(key: string, substitutions?: string | string[]): string {
  const id = chromeKey(key);
  const subs = substitutions == null ? undefined : Array.isArray(substitutions) ? substitutions.map(String) : [String(substitutions)];
  let message = '';
  try {
    // WXT's typed getMessage only lists @@* keys until prepare sees `_locales`; cast for our catalog keys.
    const getMessage = browser.i18n?.getMessage as ((name: string, substitutions?: string | string[]) => string) | undefined;
    message = (subs ? getMessage?.(id, subs) : getMessage?.(id)) ?? '';
  } catch {
    // Content-script tests and non-extension hosts have no i18n API.
  }
  if (message) return message;
  let fallback = FALLBACK[id] ?? key;
  if (subs) {
    for (let i = 0; i < subs.length; i++) {
      fallback = fallback.replaceAll(`$${i + 1}`, subs[i]!);
    }
  }
  return fallback;
}
