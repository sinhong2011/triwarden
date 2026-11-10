import { browser } from 'wxt/browser';
import { t } from './i18n';
import type { Reply, Request } from './protocol';

/** Ask the background script (which relays to the app). Never throws: failures come back as `ok: false`. */
export async function send(request: Request): Promise<Reply> {
  try {
    return (await browser.runtime.sendMessage(request)) ?? { ok: false, error: t('noAnswer') };
  } catch (error) {
    return { ok: false, error: String(error) };
  }
}
