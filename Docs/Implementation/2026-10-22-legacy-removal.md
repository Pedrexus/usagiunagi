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
