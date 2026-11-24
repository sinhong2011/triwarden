# Server compatibility

Triwarden is a client. It talks to Vaultwarden and to the official Bitwarden cloud, and both keep changing the
requests they accept and the responses they send. This page says which behaviour we test against which server, and
what to check when a server changes. Becoming a Bitwarden-compatible server is out of scope.

## What runs where

| Server | How | When |
| --- | --- | --- |
| Vaultwarden **1.37.5** (current) | `DevServerTests` over HTTPS against a disposable native build, seeded by `DevServer/seed.py` | Every PR and `main` push (`.github/workflows/ci.yml`, *Vaultwarden 1.37.5 integration*) |
| Vaultwarden **1.30.5** (legacy) | The same tests, to keep older request and response shapes working | Every PR and `main` push (*Vaultwarden 1.30.5 integration*) |
| Synthetic future items | `--selftest-compatibility`, offline, no server | Every PR and `main` push (*Build app*) |
| Vaultwarden (your dev server) | `make selftest`: the whole account lifecycle inside the signed app | By hand, before a release |
| Bitwarden cloud US / EU | `make selftest-cloud`, with an empty test account | By hand, before a release that touches login, sync or writes |

The server revisions and their Rust toolchains are pinned in `ci.yml`; see
[RELEASING.md](RELEASING.md#ci-and-release-gates) for how to move the pin. Keep exactly one legacy pin unless a
newer one replaces it.

## Behaviour matrix

✅ automated in CI · 🧑 by-hand self-test · — not tested there

| Behaviour | VW 1.37.5 | VW 1.30.5 | Bitwarden cloud | Where |
| --- | --- | --- | --- | --- |
| Login (PBKDF2), sync, decrypt | ✅ | ✅ | 🧑 | `pbkdf2LoginAndSync`, `CloudSelfTest` |
| Login (Argon2id) | ✅ | ✅ | — | `argon2idLoginAndSync` |
| Wrong password refused | ✅ | ✅ | — | `wrongPasswordIsRejected` |
| Authenticator two-step login (challenge, then success) | ✅ | ✅ | 🧑 | `totpChallengeThenSuccess`; 1.37+ issues the key itself (`seed.py`) |
| New-device email code | — | — | 🧑 | `CloudSelfTest` (cloud only) |
| Offline unlock, refresh token, resume | ✅ | ✅ | 🧑 | `offlineUnlockAndRefreshToken` |
| Server config and password hint | ✅ | ✅ | — | `serverConfig`, `passwordHintRequestSucceeds` |
| Live sync notifications | ✅ | ✅ | — | `liveSyncNotifiesOnChange` |
| Create, edit, Trash, restore, delete | ✅ | ✅ | 🧑 | `createEditTrashRestoreDelete` |
| Cards, identities, custom fields | ✅ | ✅ | 🧑 | `cardPropertiesAndCustomFields` |
| Passkeys stored on a login | ✅ | ✅ | 🧑 | `passkeyRoundTrip` |
| Attachments | ✅ | ✅ | 🧑 | `attachmentRoundTrip` |
| Organizations and collections (decrypt, create in a collection) | ✅ | ✅ | — | `organizationItemsDecrypt`, `createInExistingCollection` |
| Send (text, file, password, access by a recipient) | ✅ | ✅ | 🧑 create only | `sendRoundTrip`; 1.37.5 uses the `send_access` token grant |
| Import that the server accepted but whose reply was lost | ✅ | ✅ | — | `acceptedImportWithLostResponseIsNotResent` |
| One expired account doesn't block another | ✅ | ✅ | — | `expiredAccountDoesNotBlockHealthyAccount` |
| Equivalent domains from sync | 🧑 | 🧑 | — | `make selftest` |
| Emergency access, master-password change, 2FA on/off | 🧑 | 🧑 | — | `make selftest` |
| Bank accounts, driver's licences, passports (types 6–8): decode, create, lossless edit, move, export/import | ✅ (offline) | ✅ (offline) | ✅ (offline) | `DocumentTypesTests`, `--selftest-compatibility`; live: `documentTypesRoundTrip` and `make selftest` on a server that stores them (`TRIWARDEN_DEV_DOCUMENT_PORTS`; Vaultwarden 1.37.4 does, 1.30.5 answers `Invalid type`) |
| Unknown future item types (shown, kept losslessly, never written) | ✅ (offline) | ✅ (offline) | ✅ (offline) | `--selftest-compatibility`, `CipherCompatibilityTests` |

When you add a server behaviour, add its row here in the same pull request.

## Checklist for a server API change

Use this when a new Vaultwarden or Bitwarden release changes a request or response, or when you add a call.

- **Field case.** Servers send both `camelCase` and `PascalCase`. Decode with `JSONDecoder.vaultwarden`, never a
  plain `JSONDecoder`, and add a fixture for each spelling to `DecodingTests`.
- **Required write fields.** Newer servers refuse bodies older ones accepted. Cipher writes name the key they were
  encrypted for (`encryptedFor`; refused with 422 since web-v2025.6.0). Check the server's request models for
  newly required fields, and send them only where every pinned server accepts them, or behind a fallback.
- **Moved or removed routes.** Prefer trying the new route and falling back on the old one's 404/405, as Send
  access does (`sendAccessToken` in `VaultClient.swift`). Keep the fallback until the legacy pin no longer needs it.
- **Registration and two-step login.** Registration and authenticator setup change shape between releases (1.37+
  issues the authenticator key and wants a `userVerificationToken`). Update `DevServer/seed.py` for both pinned
  servers, not only the newest.
- **Unknown item types.** Never drop or rewrite an item type we don't understand: show it, keep its raw payload and
  refuse edits before any request (`CipherEditor.CompatibilityError`). Extend `--selftest-compatibility` if a new
  type needs its own handling. A type becomes writable by adding it to `CipherEditor.Kind` with its JSON object
  (`propertyObject`); for a document-style type, list its fields in `DocumentField` so the form, detail, KeePass
  export and search pick it up. Keep a higher number (99) as the forward-compatibility probe in the tests.
- **Loud failures.** A server refusing a request with 400 or 422 during any `--selftest` is printed as
  `SERVER REJECTED REQUEST (…)` and fails the run, even when no later check looks at the item. In `DevServerTests`
  the thrown `APIError.http` fails the test with the server's message. Don't catch these with `try?` in tests.
- **Both pins.** Run the integration tests against both pinned servers (CI does). When the newer one needs a
  different shape, keep the older one working until its pin moves.
- **Release notes.** If the change alters what someone sees or can do (a sign-in step, an error message, a Send
  link), write it up as described in [RELEASING.md](RELEASING.md#release-notes).
