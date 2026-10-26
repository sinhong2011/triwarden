# macOS 15 compatibility feasibility note

Date: 2026-10-26. Replaces the note of 2026-10-10.

Issue: [#112](https://github.com/sinhong2011/triwarden/issues/112). Parent: [#105](https://github.com/sinhong2011/triwarden/issues/105).

## Purpose and scope

This note answers one question. Can Triwarden lower the official minimum from macOS 26 to macOS 15 (Sequoia)?
It covers the API surface, the product surfaces, the build and CI options, and the release process.

This note now includes macOS 15 runtime evidence. A Sequoia 15.6.1 VM ran the build.
Section 8 lists what the run proved and what it did not prove.

## Conclusion

**Recommendation: staged go, with the first runtime gate passed.**

The code change is small. Two macOS 26 APIs remain, at three call sites. All have a working fallback.
The fallback build ran on macOS 15.6.1 without a crash.

Do not change the public minimum yet. These steps remain:

1. Merge the code fallbacks and lower the deployment target. Keep the public minimum at 26.
2. Add a `macos-15` CI job. This gives automatic Sequoia coverage on every change.
3. Test the signed build surfaces that an unsigned build cannot cover. See section 8.
4. After those pass, change the public minimum to 15.

Section 7 gives the go/no-go criteria.

## Test method and environment

Compile-time checks:

- Host: macOS 27.0.1. Xcode 27.1 (27A9275). SDK macOS 27.0.
- Base commit: `b768927`. The fallback code was uncommitted work in the worktree.
- Method: copy the tracked tree. Lower both minimums to 15. Build. Record every error.

Runtime checks:

- Guest: UTM virtual machine, macOS 15.6.1 (24G90), arm64, 98 GB free.
- Build: Debug, arm64, `MACOSX_DEPLOYMENT_TARGET=15.0`, unsigned.
- Transfer: `scp` of the 75 MB app bundle. The VirtioFS share was not available. See section 8.
- The guest ran the app, its self-test, and its snapshot renderer. The guest has no Xcode.

The build uses the current SDK. It does not use an older SDK. The deployment target is the only change.

## 1. macOS 26 API surface

The compiler found three API uses that need macOS 26. All three are in `App/Sources/VaultView.swift`:

| Line | API | Fallback needed |
| --- | --- | --- |
| 309 | `sharedBackgroundVisibility(.hidden)` on the header toolbar item | Yes |
| 2954 | `ToolbarSpacer(.flexible)` | Yes |
| 2957 | `sharedBackgroundVisibility(.hidden)` on the item actions toolbar item | Yes |

`sharedBackgroundVisibility` applies to `ToolbarContent` only. You cannot put it in a `ViewModifier`.
The fallback must branch inside the `.toolbar { }` builder. The compiler rejects the modifier form.

This note tested one fallback design:

- Header item: duplicate the `ToolbarItem` in an `if #available(macOS 26.0, *)` / `else` pair.
  The macOS 26 branch adds `.sharedBackgroundVisibility(.hidden)`. The other branch does not.
- Item actions: the macOS 26 branch keeps `ToolbarSpacer(.flexible)` and hides the shared background.
  The other branch uses `ToolbarItem(placement: .primaryAction) { actions }`.

This design compiles for Debug, Release, and universal Release. It is an experiment, not a finished design.
The macOS 15 layout is not verified. Without `ToolbarSpacer`, the system places the actions at the trailing edge.
Check the result on Sequoia before you merge.

### Correction to the earlier note

The note of 2026-10-10 reported a "SwiftUI type-check timeout" as a separate problem.
That is not correct. The timeout is a side effect of the unavailable symbols.
When the availability branches are correct, the timeout does not occur. This work needs no extra step.

### APIs that are already available on macOS 15

The compiler reports every symbol that is newer than the deployment target. After the three branches
from the table above, the compiler reports no more. So no other SwiftUI call in the app, the AutoFill
extension, or the shared code needs a change.

The audit also checked the main calls by name:

| API | Minimum |
| --- | --- |
| `toolbar(removing:)` | macOS 14 |
| `toolbarBackgroundVisibility(_:for:)` | macOS 15 |
| `containerBackground(for:)` | macOS 14 |
| `windowResizability(_:)` | macOS 13 |
| `restorationBehavior(_:)` | macOS 15 |
| `defaultLaunchBehavior(_:)` | macOS 15 |
| `onScrollGeometryChange` | macOS 15 |
| `onScrollPhaseChange` | macOS 15 |
| `scrollPosition(_:)` with `ScrollPosition` | macOS 15 |
| `onGeometryChange(for:of:action:)` | macOS 15 |

The app does not use `glassEffect`, `GlassEffectContainer`, `safeAreaBar`, or `backgroundExtensionEffect`.
The app does not use `WebView`.

The code base has no `@available` declarations today. The new branches will be the first.

## 2. Capabilities that need no change

The audit checked the system frameworks against the macOS 15 SDK headers and the system symbol database.

- **AutoFill, one-time codes:** `ASOneTimeCodeCredential`, `ASOneTimeCodeCredentialIdentity`,
  `ASOneTimeCodeCredentialRequest`, and `prepareOneTimeCodeCredentialList` are macOS 15.0.
- **AutoFill, passkeys:** the passkey entry points are macOS 14.0.
  `performPasskeyRegistrationWithoutUserInteractionIfPossible` is macOS 15.0.
- **AutoFill, settings:** `ASSettingsHelper` is macOS 14.0.
- **Touch ID:** `LAAuthenticationView` is macOS 12.0.
- **QR scanner:** `SCContentSharingPicker` is macOS 14.0.
- **Launch at login:** `SMAppService` is macOS 13.0.
- **SF Symbols:** the app uses 79 symbol names. All 79 are available at or before macOS 15.
  The audit checked each name against the system `name_availability.plist`.
- **Dynamic symbols:** the app has no weak-linked macOS 26 symbols and no runtime lookup of one.
  The one private selector, `_statusItems`, is guarded with `responds(to:)`.

No capability must be removed to target macOS 15.

## 3. Product surfaces to test on Sequoia

A claim of support needs evidence for each surface below.
The "CI" column shows whether a `macos-15` runner can cover the item without a person.
The "VM" column shows the result of the 2026-10-26 run in section 8.

| Surface | CI | VM | What must pass |
| --- | --- | --- | --- |
| Launch and first run | Yes | Pass | Window opens. Menu bar item appears. No crash. |
| Sign in and sync | Yes | Not run | Sign in. Initial sync. Incremental sync. Offline error path. |
| Unlock and lock | Partly | Not run | Master password unlock. Auto-lock. Keychain persistence across a relaunch. |
| Touch ID unlock | No | Not run | Enrolment prompt. Unlock. Fallback to password. |
| Item work | Yes | Render only | Create, edit, delete, search, Command Palette. |
| Clipboard | Partly | Not run | Copy. Expiry timer. Clear. |
| AutoFill, password | No | Blocked | Enable in System Settings. Fill. Save. |
| AutoFill, one-time code | No | Blocked | Fill a code from an item. |
| AutoFill, passkey | No | Blocked | Register and sign in with a passkey. |
| Safari extension | No | Blocked | Enable. Fill. Save. |
| Auto-Type helper | No | Not run | Grant Accessibility. Type into another app. |
| SSH agent | No | Not run | Approval card. Signature by `ssh`. |
| Updates | No | Partial | Sparkle loads. No update ran. |
| Appearance | Partly | Pass | Light and dark. Narrow window. Toolbar layout from section 1. |
| Upgrade path | No | Not run | Install a 26 build, then update to a 15 build. Confirm settings and vault survive. |

"Blocked" means an unsigned build cannot test the surface. Section 8 gives the cause.
"Render only" means the screen renders, but no one used the control.

The last row matters. A user on macOS 26 will receive a build with a lower minimum.
That direction is safe, but test it once.

## 4. Build and CI

### What compiles today

The audit lowered `project.yml` to `macOS: "15.0"` and `Packages/VaultCore/Package.swift` to `.macOS(.v15)`.
It applied the fallback from section 1. Results:

| Build | Result |
| --- | --- |
| Debug, arm64 | BUILD SUCCEEDED |
| Release, arm64 | BUILD SUCCEEDED |
| Release, arm64 + x86_64 | BUILD SUCCEEDED |
| `swift build` and `swift test` in VaultCore | 19 tests pass |

Every bundle reports `LSMinimumSystemVersion` 15.0:
the app, the AutoFill extension, the Safari extension, the Auto-Type helper, the `tw` tool, and the TriCrypto bundle.
The main binary reports `minos 15.0` for both architectures. Sparkle reports 12.0 and needs no change.

### A Sequoia runner exists

The earlier note said CI only runs on macOS 26. That is no longer a limit.
GitHub hosts a `macos-15` arm64 image. The image runs macOS 15.7.9 and includes Xcode 26.0.1 to 26.3.
The project needs Swift 6.2, and Xcode 26.x supplies it.

So the project can run real Sequoia jobs. Add one job to `.github/workflows/ci.yml`:

- `runs-on: macos-15`
- Select Xcode 26.3 with `xcode-select`.
- Run the existing steps: build, `IconStoreTests`, the compatibility self-test, and `CISmokeTests`.
- Run the Vaultwarden integration tests.

This covers most of section 3 automatically and costs no person-hours per release.

### What CI cannot cover

The runner is ephemeral and unsigned. These items stay manual:

- AutoFill, Safari extension, and Auto-Type need a signed build and a user session in System Settings.
- Touch ID needs enrolled hardware.
- The Sparkle update needs a published release.

## 5. Release process

Do not gate every publish on a human Sequoia tester. That adds a person to each release and it will stall.

Use this split:

- **Automatic gate, every release:** the `macos-15` CI job must pass. This is not optional.
- **Manual gate, once:** a person runs the section 3 list on a real Sequoia Mac before the first release that claims 15.
- **Manual check, best effort:** after that, the [#105](https://github.com/sinhong2011/triwarden/issues/105) requester
  tests each release that changes the minimum, the toolbar, or AutoFill. Treat a report as a bug report, not a veto.

### Release files that hard-code macOS 26

These must change in the same change that lowers the minimum. Until then they stay correct.

| File | Current value | Needed value |
| --- | --- | --- |
| `scripts/release.sh:129` | `depends_on macos: :tahoe` | `depends_on macos: :sequoia` |
| `README.md` lines 9, 15, 29 | macOS 26 | macOS 15 |
| `site/messages/*.json` (9 locales, 3 keys each) | macOS 26 | macOS 15 |
| `site/src/components/Home.astro:40` | `macOS 26 or later` | `macOS 15 or later` |
| `site/src/components/guide/SshGuide.astro:30` | `macOS 26 or later` | `macOS 15 or later` |

The Homebrew cask is the most important row. With `:tahoe`, `brew` refuses to install on Sequoia.
The user sees an error before the app ever starts.

Sparkle needs no change. `generate_appcast` reads `LSMinimumSystemVersion` from the built app
and writes `sparkle:minimumSystemVersion` into the appcast. A correct build produces a correct appcast.

## 6. Risks

1. **Toolbar layout on Sequoia.** Confirmed correct. The snapshot render shows the item actions at the trailing
   edge, in light and dark. See section 8.
2. **App icon at large sizes.** `AppIcon.icns` has four representations: 16x16, 16@2x, 128x128, and 128@2x.
   It has no 32, 256, 512, or 1024 representation. The macOS 26 build produces the same files, so the lower
   target does not cause this. On Sequoia, `sips` reports a maximum of 256 pixels for the `.icns`.
   This is a real gap. It is not new, and it does not block launch. Fix it before the public claim.
3. **Extension activation.** Not yet tested. The AutoFill and Safari extensions need a signed build.
   System Settings paths and prompts differ between macOS versions. See section 8.
4. **A second minimum to maintain.** You must check every new API against 15 from now on.
   The `macos-15` CI job makes a mistake fail the build, which limits this risk.
5. **Unsigned builds cannot register extensions.** An ad-hoc signature strips the entitlements that
   `pluginkit` needs. This limits what a local QA build can prove. It is not a macOS 15 defect.

## 7. Recommendation and go/no-go criteria

**Staged go.** Do not ship Sequoia support in one step.

### Stage 1: code and CI, no public claim

Do these together:

1. Add the availability branches from section 1. Check the layout on macOS 26 did not change.
2. Lower `project.yml` and `Packages/VaultCore/Package.swift` to 15.
3. Add the `macos-15` CI job from section 4.
4. Keep README, the site, and the cask at macOS 26.

**Go to stage 2 when:** the `macos-15` job passes on `main` for three consecutive runs.

### Stage 2: signed build checks

Build, sign, and notarize a release candidate. Test the surfaces that an unsigned build cannot reach:

- Sign in, sync, and unlock on a real Sequoia Mac.
- AutoFill fills a password and a one-time code.
- The Safari extension fills a login.
- The app icon is sharp in the Dock.
- The upgrade path from a 26 build.

**Go to stage 3 when** these pass with no crash.

The VM run already passed these: launch, no crash, window and menu bar item, offline self-test,
light and dark render, toolbar layout, and Sparkle load.

### Stage 3: public claim

Change README, the site in all locales, and the cask to macOS 15. Release.

**Stop and keep the minimum at 26 if** any of these occur:

- A crash on launch, unlock, or sync that has no quick fix.
- AutoFill cannot be enabled on Sequoia.
- The Safari extension does not load.
- The toolbar layout is broken and the fallback has no simple alternative.

### What this note does not prove

- Intel runtime behaviour. The universal build compiles, but no one ran it on Intel.
- The signed and notarized release on macOS 15.
- The updater on macOS 15. The Sparkle framework loads, but no update ran.
- Extension activation. An unsigned build cannot register the extensions. See section 8.

## 8. macOS 15 runtime results

Date: 2026-10-26. Guest: macOS 15.6.1 (24G90), arm64, UTM.

### What passed

| Check | Result |
| --- | --- |
| App launches | Pass. Process starts and stays up. |
| No crash | Pass. No crash report. Main thread active after 44 seconds. |
| Window and menu bar item | Pass. Main window 1369x994 on screen, alpha 1.0. Menu bar item present. |
| Offline compatibility self-test | Pass. 24 checks, 0 failures. |
| UI render, light | Pass. 27 screens render. |
| UI render, dark | Pass. 25 screens render. |
| Toolbar fallback layout | Pass. Item actions sit at the trailing edge. |
| Sparkle loads | Pass. Framework and both XPC services load. Minimum 12.0. |
| Memory | 205 MB resident with the demo vault. |

The self-test covers the shared decoder and the app's mutation boundaries.
It is the same test that CI runs with `--selftest-compatibility`.

The UI render uses the app's own `--snapshot` mode. That mode draws SwiftUI views directly to an image.
It does not use the window server. This was necessary because the VM does not composite windows into a
screen capture. A control test with System Settings showed the same blank capture. The cause is the VM
display, not Triwarden.

The snapshot images show the full vault window: sidebar, item list, item detail, one-time code, passkey row,
watchtower row, attachments, and the toolbar.

The same `--snapshot` run on the host gave a reference image. The host runs macOS 27.0.1, so this is not a
clean macOS 26 against macOS 15 pair. Both images put the toolbar actions at the trailing edge, in the same
order. The section order and the spacing match. The images are not byte-identical for two reasons that do
not come from the deployment target:

- The host render shows cached site icons. The guest render shows letter placeholders.
- The host image is 28 pixels taller. The window frame measurement differs.

Treat the toolbar placement as confirmed. Do not use the images as a pixel comparison.

### What did not pass, and why

**Extension registration.** `pluginkit` does not list the AutoFill or Safari extension for this build.
The cause is the signature. An unsigned or ad-hoc build has no provisioning profile, and `codesign --deep`
with an ad-hoc identity strips the entitlements that the extensions need. This is a property of local QA
builds. It is not a macOS 15 behaviour. Test extension activation with a Developer ID build.

**Screen capture of a live window.** The VM returns a desktop-only image. This affects every app in the
guest, including System Settings. Do not use screen capture to judge this VM.

**VirtioFS share.** The share stopped serving new content after a directory replace. A force unmount made
it unreachable, and remounting needs `sudo` in the guest. The app was copied with `scp` instead. Fix the
share before the next QA run, or expect to use `scp`.

## References

- [ASOneTimeCodeCredential](https://developer.apple.com/documentation/authenticationservices/asonetimecodecredential)
- [ASSettingsHelper](https://developer.apple.com/documentation/authenticationservices/assettingshelper)
- [GitHub Actions runner images](https://github.com/actions/runner-images)
