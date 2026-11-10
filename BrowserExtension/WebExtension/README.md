# Triwarden browser extension

WXT + Solid content/background scripts for Chrome, Firefox and Safari. The native app decides matches, Touch ID and saves; this package is the page UI and bridge relay.

## Localization

User-visible strings live in `locales/` (`en` is the source of truth). `@wxt-dev/i18n` builds Chrome/Firefox `_locales/*/messages.json` at prepare/build. The UI follows the **browser UI language** — there is no in-extension language setting.

First locales: `en`, `zh_TW` (Traditional Chinese / zh-Hant), `zh_CN` (Simplified / zh-Hans), `ja`. More app locales (ko, fr, es, th) can reuse the same files later.

Call `t('overlay.noLogins')` from `lib/i18n.ts` (falls back to English in Vitest when `browser.i18n` is absent).

### Bridge errors

When Triwarden is unreachable, the native host returns stable `code` values (`app_not_running`, `connection_disabled`) plus an English `error` string for logs. The extension **translates from `code`** so the Safari banner and overlay notes match the browser language. Other failures still show the app's `error` text (already localized to the app locale). See `lib/bridge-status.ts`.

Store listing copy for Chrome Web Store / Firefox Add-ons can reuse the same locale set in a separate upload step.
