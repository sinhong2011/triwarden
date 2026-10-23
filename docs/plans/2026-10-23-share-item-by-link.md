# Issue #85 — Share an item by link (prefilled Send)

**Worktree:** `.worktrees/share-by-link-85` · branch `feat/share-item-by-link` (from `origin/main` @ d33a486)

## The ask

1Password's **Share** makes a link for a single item. Triwarden has Send, but every Send starts
blank, so sharing a login today means retyping username/password/website/notes into a new text
Send by hand.

**Proposal (from the issue):** add **Share by Link…** to the item's right-click menu and to the
detail toolbar. It opens the existing New Send form already filled in:

- **Name** — the item name
- **Text** — the item's fields (username, password, website, notes), hidden by default
- Everything else stays editable (delete-after, expiry, max views, password, notes, email)

Saving copies the link, exactly like a new Send does today.

## What already exists (no new plumbing needed)

| Piece | Where | Notes |
| --- | --- | --- |
| Send compose state | `AppModel.composingSend`, `editingSend`, `newSendKind`, `newSendNonce`, `sendContextAccountIDs`, `requestedSection` | `App/Sources/AppModel.swift:418`, `:702-704` |
| Composer | `SendComposer(editing:)` | `App/Sources/SendView.swift:280`; `prefill()` at `:318` only fills from an existing *Send* |
| "New Send" launch pattern | `SidebarActions.swift:141-153` | clears context, sets kind/nonce, `requestedSection = .sends` |
| Save → copy link | `SendComposer.create()` → `model.createSend` | copies the link the same as today |
| Item context menu | `itemContextActions(_:)` | `App/Sources/ItemContextMenu.swift:6` — Copy Username / Password / Website / Notes, Edit, Clone, … |
| Detail toolbar | `HeroCard.actions` | `App/Sources/VaultView.swift:2537-2579` (`toolbarButton(...)`) |
| Reprompt gate | `AppModel.guarded(item)` | `AppModel.swift:386` — must wrap: we're extracting the password |
| Item fields | `VaultItem.username/password/websites/notes`, `fields` | `Shared/VaultModel.swift:17-27`, `:81` |

So this is a **prefill path into an existing form**, not a new feature surface. The only real
design decisions are (a) how the text is formatted, (b) where the fields are stored so the composer
can read them, and (c) which items get the entry point.

## Design

### 1. A prefill value, separate from `editing`

Add to `AppModel`:

```swift
/// A prefilled text Send for "Share by Link…" (issue #85); nil for a normal New Send.
struct SendPrefill { var name: String; var text: String; var accountId: String? }
var newSendPrefill: SendPrefill?          // cleared when the composer dismisses
```

`SendComposer.prefill()` reads `model.newSendPrefill` when `editing == nil`, after the account
resolution it already does. The composer is already re-keyed by `newSendNonce`
(`SendView.swift:64`), so seeding different items never reuses stale `@State`.

### 2. How the fields are rendered

Build the text in a small pure helper (testable in `VaultCore`, no AppKit):

```swift
extension VaultItem {
    /// "Username: …\nPassword: …\nWebsite: …\nNotes: …" plus extra fields for non-logins.
    func shareText() -> String
}
```

- Login: `Username`, `Password`, `Website` (all `websites`, one per line), `Notes`.
- Card / identity / SSH: fall back to `name` + `fields` (label: value), omitting empty values.
- One-time-code secrets are **omitted** — a TOTP seed in a link is a standing 2FA bypass.
- `hideText` starts **on** (issue: "hidden by default"); the user can turn it off.

Because real secrets go into the shared text, every call site goes through
`model.guarded(item) { … }` so reprompt-protected items ask for the master password first.

### 3. Protection: a passphrase, and one chance to copy it

A prefilled Send carries a **real password**, and a Send link is a bearer token: anyone who
receives the link can read it. So the prefill also generates a 6-word passphrase
(`PassphraseGenerator`, EFF wordlist) as the Send's own password. The link alone then opens
nothing; the recipient needs the passphrase too, which travels by another route.

The server stores only `SendCrypto.passwordHash` — **PBKDF2-SHA256, 100 000 rounds, one-way** —
so the passphrase can never be read back. That shapes the whole flow:

- **Nothing is copied automatically.** The old `copyPlain(link)` on create would silently throw
  away a passphrase the sender had just copied.
- **Create Send** (not "Create & Copy Link") makes the Send and opens a one-time sheet
  (`SendCreatedSheet`) showing the link and the passphrase, each with its own copy button. The
  passphrase is masked until revealed, and the sheet says to send it separately from the link.
- **Done** closes it and drops both: `AppModel.createdSend` is cleared in `onDisappear`, so the
  plaintext lives only as long as that window — the same rule `generatorHistory` follows.
- The composer's password field has **no** copy button; before creating is the only place the
  passphrase exists, and the sheet is where it is handed over.

### 4. Entry points

- **Context menu** — `itemContextActions`: "Share by Link…" with `paperplane`, in the block after
  the copy actions, only for non-deleted, supported items. No `enabled:` gate needed beyond that.
- **Detail toolbar** — `HeroCard.actions`: a `paperplane` button next to Edit, same `toolbarButton`
  helper, `.help("Share by Link…")`.
- Both call one `AppModel.shareItemByLink(_ item:)` (in `ItemContextMenu.swift`, next to the other
  item actions) that does: `leaveNewItemForm` → set prefill → `newSendKind = .text` → new nonce →
  `editingSend = nil` → `composingSend = true` → `requestedSection = .sends`.

### 5. Localization

New user-facing strings go into `App/Resources/Localizable.xcstrings` (hand-maintained, sorted by
key): "Share by Link…", "Create Send", "Passphrase", "Show/Hide passphrase", "Link", "Done", the
two passphrase notes, the sheet subtitle, and "This item has nothing to share." Each is translated
for all nine locales the catalog carries (en, ja, zh-Hans, zh-Hant, zh-HK, ko, fr, es, th).

## Scope / non-goals

- **Out:** attachments in the shared text, folder/collection items bulk-share from a multi-select,
  auto-creating the Send without review, and any new server API (Sends already exist).
- Sends are per-account; the prefill carries `item.accountId` so the Send lands in the same account
  unless the user picks another in the composer's account menu.

## Test plan

1. `make build` in the worktree (xcodegen + Debug build) — **passing**.
2. `make test` / `swift test --filter VaultwardenAPITests` — 80 tests in 15 suites, **all passing**.
   (`SSHAgentTests` hangs waiting on a socket in this environment; unrelated to this change.)
3. `--snapshot` renders for review, since the app container is TCC-protected and Screen Recording
   is off: `send-share-by-link-{light,dark}`, `send-created-{light,dark}`.
4. Manual (`needs manual test` label):
   - Login → right-click → Share by Link… → composer opens in Send: Name = item name, Text = the
     fields, Hide-text on, passphrase filled in.
   - Same from the detail toolbar button.
   - **Create Send** → one-time sheet with link + passphrase; passphrase masked until revealed;
     each copies on its own; Done closes and nothing is left behind.
   - Reopening the Send shows `Password: Required` — no way back to the passphrase, by design.
   - Reprompt-protected item asks for the master password first.
   - Deleted / unsupported items do not offer it; archived ones do.
   - Cancel → nothing created, next New Send is blank again.

## Risks

- **Secret exposure in shared text** — mitigated by `guarded()`, hide-text default, a generated
  passphrase the link alone cannot open, and never retaining that passphrase past the sheet. The
  remaining exposure is the clipboard itself: the sheet uses `copyPlain`, so a pasted passphrase
  is visible to clipboard managers and is not auto-cleared. Worth a review decision.
- The composer keys on `newSendNonce`; if the prefill changes without a new nonce the form keeps
  the old `@State`. The single launch helper always mints a nonce, so this stays correct.
