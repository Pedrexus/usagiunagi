# Legacy runtime removal — October 22, 2026

The owner requested deletion of all legacy code. This supersedes retention of the old
importers, excluded controller remnants and ClockKit face migration. Current native study
behavior remains the preservation boundary; historical import support is intentionally retired.

## Removed

- Read-only original SQLite/protobuf database importer, preference schema/archive importer,
  activation/bootstrap state machine and their importer-specific checks.
- The complete `App/WaniKaniAPI` package, SwiftProtobuf dependency, both resolution files,
  protobuf generator/plugin configuration and obsolete CI invocation bypasses.
- Former Mac JSON statistics-cache adoption and its startup/logout branches.
- Haneke cache adoption, MD5 lookup and filesystem traversal. `StudyAvatarCache` retains
  bounded decoding, injected HTTP caching/transport, cancellation and explicit-clear fencing.
- Username-based JSON iCloud mistake exchange and receipt binding/revocation execution.
  Native account-keyed binary-plist mistake sync and absolute timestamps remain.
- Excluded `AnswerChecker`, `LegacyCatalogViewController` and `FullRefreshOverlayView` remnants.
  Their preexisting owner-modified source and exact patch are preserved locally in ignored
  `.build/Reports/LegacyRemoval-20261022`; they are not shipped or recommitted.
- ClockKit principal class, face migrator and configuration. The SwiftUI Watch app and four
  WidgetKit accessory families remain. The retired character-picker state falls back to Reviews.
- Obsolete baseline population/writer and importer handoff modes in current targets and Actions.
  `NativeStoreSnapshot.swift` retains the reader/comparer; the checksum-pinned historical writer
  source remains excluded from both current target graphs, alongside its immutable archive.
- Ignored old Pods, protobuf package products and formatter-tool build cache, approximately
  1 GB locally. Source checks no longer need the retired vendor-directory exclusions.

## Preserved native format and behavior

`StudySchemaV1.swift` is byte-identical, SHA-256
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.
The original frozen store, manifest, checksum-pinned writer source and archived writer/independent
decoder are unchanged. A checksum check catches an initial edit of the pinned writer helper;
its exact source is restored and the current read-only comparer moves to a separate file.

Minimal receipt payload declarations live in `StudyHistoricalValues`,
`StudyHistoricalPreferences` and `StudyHistoricalMistakes`. Their nominal module/type identities,
stored fields/defaults and Codable shape remain unchanged. They decode existing native stores;
they cannot read an old database, install credentials, select a writer or import settings.
Removing these fields/types requires a separately validated versioned schema transition.

`StudyAccountState` now has its own file and only the native download initializer. Existing
model-actor transactions, revisions, pending reviews/notes, account isolation, recovery,
generation validation and synchronization ownership remain. The Core Data boundary protects
native SwiftData generations; no shipping source imports SQLite3 or contains feature SQL.

Current fixtures apply typed native downloads or insert isolated test-only native records.
They no longer keep an importer alive solely to seed modern reviews, settings or diagnostics.
Grading, kana conversion, subject colors, lesson ordering, native media and adaptive screens
remain in their current owners. Narrow UIKit IME/settings-service adapters are current platform
boundaries and remain; no storyboard/controller host is restored.

## Current platform boundaries

Source audit after `99d5477d`: app-owned screens share SwiftUI. The following current
boundaries are retained for behavior, not as alternate legacy screens. This inventory
describes the checked implementation; it does not claim that future SDKs cannot replace them.

| Boundary | Current owner and reason | What removal must preserve |
| --- | --- | --- |
| UIKit text entry | `Shared/Sources/StudyUI/Reviews/StudyAnswerInput.swift`: one `UIViewRepresentable`/`UITextField` adapter and one Objective-C target action for text changes | Japanese keyboard choice, marked-text composition, caret-safe romaji conversion, paste/cut and retry-on-delete. Mac uses native SwiftUI input. |
| System notification settings | `Shared/Sources/StudyUI/Settings/NotificationSettingsSection.swift`: UIKit settings URL on iOS; AppKit application lookup/open on Mac | Permission recovery and resuming the original request after returning. The notification form itself is shared SwiftUI. |
| Mac competing-process guard | `App/Application/StudyApplicationOwner.swift`: `NSWorkspace.runningApplications` before opening the native store | Refusal while another known app process owns the data. The older bundle identifier here is a safety check, not an importer. |
| Audio and background execution | `AppleStudyAudioPlayback`, `AppleVoiceCapture`, `StudyApplicationOwner`: iOS audio-session and BackgroundTasks branches | Interruption/mixing policy and background refresh. These service capabilities differ from presentation and should not become a generic layout switch. |
| Paired Watch transport | `App/Watch`: WatchConnectivity and bounded recording; phone owns recognition, grading and writes | Account/revision fences, pause, microphone exclusivity and delivery limits. Watch views are SwiftUI; complication views use WidgetKit. Physical continuity remains unaccepted. |
| Native-store protection | `Shared/Sources/StudyPersistence/StudyStoreGeneration.swift`: Core Data metadata/store-file coordination underneath SwiftData generations | Store validation, durable generation publication and recovery. Feature queries and transactions remain SwiftData; this is not FMDB or a SQL feature path. |

Other iOS-only UI modifiers configure keyboard type/capitalization or expose settings whose
service exists only on that platform. Removing those guards without equivalent behavior
would hide a platform difference rather than unify it. No retained bridge requires disabling
a feature under the owner's “replace first; preserve functionality” instruction. Any future
replacement must pass the existing input, storage and service checks before deletion.

## Intentional compatibility retirements

An old original-app database or JSON snapshot no longer imports automatically. A fresh
connection downloads WaniKani's current state; that cannot recover unsent original-app answers
or local-only notes. Original files on the user's devices are not opened, modified or deleted.
Existing already-native saved work still opens with the same schema and decoder identities.

Old local-time mistake hints and username-based iCloud values no longer contribute to Recent
Mistakes. Their persisted original text/receipts remain intact; current native timestamps and
account-keyed archives continue working. Installed ClockKit faces no longer migrate automatically;
users can choose the current WidgetKit complication.

## Validation

No automated test or review/microphone session was executed. The owner's tests-last order remains
in force. Compiling verification sources does not establish that their assertions passed.

- iPhone Debug and Watch Debug builds pass through Mainboard with no compiler errors/warnings.
- Native Mac Release builds successfully with no compiler errors/warnings.
- Shared test products and the native persistence probe compile successfully without execution.
- iPhone app/test products compile with `build-for-testing`; no test runner/app was launched.
- Initial scoped lint identifies an obsolete watchOS 10 branch, which is removed. Removing old
  ignore entries also exposes abandoned local Pods; those obsolete caches are removed rather than
  formatted or suppressed. These failed trials remain in local result logs.

Exact build, lint and rule logs are retained under `.build/Results/LegacyRemoval-*20261022.log`.
Native AppIntents metadata tools emit their separate no-framework extraction notice; native build
summaries report zero compiler/analyzer warnings. Physical speech, signed services, account sync,
original-app usability and the broader storage/modernization acceptance gates remain open in TASKS.

Final full lint checks 435 files, rewrites none and passes every configured step. The rule inventory
completes with 211 findings across 98 rules, down from 234 before deletion; those review advisories
are not a clean rule gate. Current Debug iPhone (including its Watch/widget) and Mac Release bundle
inspection both report no forbidden retired symbols, including SwiftProtobuf, WaniKaniAPI, FMDB,
the importer and ClockKit controller. The full five-file frozen-fixture checksum check passes.

Build evidence: iPhone `build-43dffc64b6b74ba3a996580e76e54634`, Watch
`build-b22c785be0d8462d9cb2633b8f10dcf4`, Mac Release
`build-33defeed6dee48fa9bd4c8ebd7ce73f7`, final iPhone compile-only test products
`build-for-testing-8dd632f84e4140cc954d13a7bfc0dd4f`. The final probe build completes separately;
none of the test/probe executables runs. Later source-formatting changes are nonsemantic; the
final iPhone products include the simplified watchOS 27 widget branch.

The staged Swift delta is 125 added / 2,247 deleted production lines (2,122 net fewer), counting
app/shared runtime and the retired package manifest, excluding fixtures, tests and probe code.
Verification Swift changes are 579 added / 2,723 deleted lines; native assertions remain while
importer-only suites retire. These are physical diff lines against `7378c120`, not an executed
coverage or behavioral-equivalence claim. Frozen sources and evidence are excluded from savings.

## Follow-up reference audit

Rechecked tracked production Swift method/type references after the earlier removals. Methods
with no direct source call sites are system protocol/delegate callbacks or `callAsFunction`;
none establishes another safe deletion. This lexical check is an audit aid, not whole-program
reachability proof. Resource generators and their source data are still referenced by documented
regeneration workflows and are retained. There are no tracked Go, Ruby, Python, Objective-C or
protobuf source files in the current checkout.

Removed the workspace's obsolete `IDEDidComputeMac32BitWarning` acknowledgment metadata and
replaced stale current-development instructions for already deleted importer/protobuf targets.
No runtime code or dependencies changed in this follow-up. Prior removals include the unused
UploadCoordinator and its isolated tests, plus the duplicate Watch scheme (`e7a606ca`).
Required native callbacks, Japanese IME integration, Codable identities and frozen SwiftData
validation fixtures remain; age or a historical name alone is not evidence that code is dead.

## Final linker/reference cleanup

Removed the unused explicit `-lcompression` link and `HEADER_SEARCH_PATHS = .` from
both project configurations. No current source imports Compression or uses local C headers.
Corrected catalog, SRS and vocabulary comments that still described the deleted importer.
The SRS fallback remains active for existing offline caches; persisted field names, mnemonic
content, framework callbacks and the Japanese IME bridge remain required.

Repeated tracked Swift declaration/reference and resource checks found no further confirmed
unused implementation. This is not a whole-program proof of absence. No tracked Objective-C,
Go, Python, Ruby or protobuf sources remain. Historical SwiftData readers and fixtures are
retained to verify saved-data compatibility, not shipped as runtime implementations.

Mainboard lint passes for all 436 files. The generic iOS simulator build passes with zero
warnings/errors (`build-8d56a981775f4358bc61900f83f731d6.xcresult`).
Native Mac build also passes with zero warnings/errors
(`build-c3bf675ed5a7413b9c2b7160ac6f2932.xcresult`). No runtime code changed in this pass.

## Production-only reachability audit

A second declaration/reference audit excludes test callers before classifying production use.
It identifies three test-only mutation entry points: `acknowledgeReview`,
`acknowledgeMaterial` and `mergeMaterials`. Removed their 43 lines from the shipping
StudyPersistence sources and placed the existing fixture transitions in
`Shared/Tests/StudyPersistenceTests/NativeStoreFixture.swift`, without public visibility.
Production continues using validated upload and atomic refresh transactions. No persisted
model, decoder identity, account data or frozen fixture changed. This reduces the production
API surface; it is not a claim of fewer total repository lines.

`saveSnapshot` remains used by the independent persistence probe. Other single-reference
production declarations are framework entry points/delegate callbacks. Historical Codable
fields remain part of saved data. The audit found no tracked Go, Ruby, Python, Objective-C,
protobuf, storyboard or XIB source to delete. Lexical reference checks are not whole-program
reachability proof. Preexisting UI acceptance edits remain outside this cleanup.

Mainboard lint passes all 436 files; `git diff --check` passes. Focused existing storage tests
are recorded in `.build/Results/DeadCode-Cleanup-Tests-20261022.log`.
The focused run completed successfully: 36 tests across StudyStoreTests, NativeRefreshTests,
CatalogFreshnessTests and ReviewRecoveryTests. The unrelated in-progress iPhone acceptance
run uses its previously compiled products; this cleanup does not establish its outcome.
