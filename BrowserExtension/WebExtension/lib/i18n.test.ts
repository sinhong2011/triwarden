import { describe, expect, it } from 'vitest';
import { t } from './i18n';
import en from '../locales/en.json';
import ja from '../locales/ja.json';
import zhCN from '../locales/zh_CN.json';
import zhTW from '../locales/zh_TW.json';

/** Every leaf key path in the English catalog must exist in each locale file. */
function leafKeys(obj: Record<string, unknown>, prefix = ''): string[] {
  const keys: string[] = [];
  for (const [key, value] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === 'string') keys.push(path);
    else if (value && typeof value === 'object') keys.push(...leafKeys(value as Record<string, unknown>, path));
  }
  return keys;
}

describe('locales', () => {
  const expected = leafKeys(en as Record<string, unknown>);

  it.each([
    ['zh_TW', zhTW],
    ['zh_CN', zhCN],
    ['ja', ja],
  ] as const)('%s has the same keys as en', (_name, catalog) => {
    expect(leafKeys(catalog as Record<string, unknown>).sort()).toEqual([...expected].sort());
  });

  it('falls back to English when browser.i18n is absent', () => {
    expect(t('extName')).toBe(en.extName);
    expect(t('bridge.appNotRunning')).toBe(en.bridge.appNotRunning);
    expect(t('overlay.codeValidFor', '3')).toBe('Code valid for 3 more seconds');
    expect(t('gen.increase', en.gen.length)).toBe(`Increase ${en.gen.length}`);
  });
});
