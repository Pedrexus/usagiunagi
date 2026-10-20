# Swift and SwiftData migration specification

Updated October 20, 2026. This is the execution specification for the remaining modernization. [TASKS.md](TASKS.md) tracks current status; historical validation receipts remain evidence for their stated source and scope. A plan item is complete only after its acceptance gate passes. FMDB removal and complete feature parity are still open.

## Outcome and boundaries

Ship one shared SwiftUI application for iPhone, iPad and native Mac, using Swift 6 and SwiftData for durable app data. Preserve WaniKani grading, lesson order, review options, offline work, notes, exclusions, account identity and synchronization. Retain WaniKani colors, system typography and SF Symbols, with restrained native Liquid Glass. The original Tsurukame iPad lesson/review flow remains the interaction reference. Changing frameworks must not silently change study behavior.

The repository stays in `apps/usagiunagi`, with localized 兔鰻/usagiunagi identity. Work remains on the existing development branches, with commits and no PRs or pushes. Mainboard owns development dependencies, formatters, rules, builds, tests and receipts. App-specific task scripts must not grow into a second development system.

FMDB is to be removed from app source, target membership, dependency declarations and linked products. The old custom SQLite database still needs a read-only import path for supported existing installations. That boundary must use the system reader, be isolated from feature code, and never remain a second writer. SwiftData cannot interpret arbitrary legacy FMDB tables as a native model store. Its own [default store uses Core Data internally](https://developer.apple.com/documentation/swiftdata/defaultstore); the requirement is to eliminate our handwritten feature SQL and FMDB dependency.

Durable domain data belongs in SwiftData. Credentials stay in Keychain, ordinary preferences in AppStorage/UserDefaults, transient window input in SceneStorage, and downloaded media in files. These storage roles preserve platform behavior and avoid storing credentials or large media blobs in model records. WaniKani remains the authority for assignment/review progress. CloudKit must not independently replicate the answer outbox.

## Current implementation

The production scene already uses `UsagiUnagiApp` → `StudyApplicationOwner` → `StudyAppAssembly` → shared `StudyRootView` on all three platforms. `StudyStore` is an `@ModelActor`, uses SwiftData transactions and returns Sendable values. Shared modules use Swift 6.4 tools and Swift 6 language mode. Normal iOS bootstrap reads old installations through `LegacyStudyImporter`, which already uses system SQLite3 read-only; its remaining `LocalCachingClient.databaseUrl()` reference is a path lookup, not the native writer.

The remaining DEBUG acceptance host constructs `TKMServices` and the old cache/writer. Old controllers are also still compiled for iOS. Removing only their launch route would leave source and dependency debt. Native recent-mistake practice reads local account progress, but the original cross-device timestamp service still belongs to `LocalCachingClient`. Native diagnostics also directly uses SQLite3 to back up the SwiftData store. These are concrete deletion prerequisites.

Shared grading, kana conversion, session policy, sync/recovery, lessons, reviews, subjects, settings, Home and charts are implemented. Automated evidence includes 479 shared test functions and selected native acceptance; each new checkpoint must identify its own fresh runs. Physical Japanese IME, microphone/model behavior, signed upgrades, OS notifications/background work and paired watch transfer still need device evidence. Bundled free levels contain display references, not a complete authenticated exercise catalog.

## Requirements

| ID | Required result | Completion evidence |
| --- | --- | --- |
| M1 | One production SwiftUI feature implementation across iPhone, iPad and Mac | Shared screens and state, native builds and equivalent end-to-end flows; platform conditions confined to a documented capability boundary |
| M2 | SwiftData owns durable application state and every normal write | Native schema/store APIs, account-isolated queries, atomic session/outbox transitions, no FMDB linkage or feature SQL |
| M3 | Existing work survives migration and restart | Real historical schema fixtures, current-native store upgrades, interrupted handoff/restart tests, immutable original source retained on failure |
| M4 | Lesson/review behavior is preserved | Typed/Anki/voice, incorrect/correction/defer/wrap-up, draft pause/resume, lesson teaching/quiz and missed-subject results verified against existing policies |
| M5 | Cross-device and background behavior has one owner | Timestamp merge, notifications, background scheduling, links and watch transfer fed from committed native state, with logout/cancellation/account-change tests |
| M6 | Statistics remain understandable and credible | Shared plots, verified coverage lists, forecast/backtest validation and explicit separation of coverage from exam pass probability |
| M7 | Rules guide future cleanup without inventing semantics | Syntax-backed Swift checks, current-toolchain compilation, correctness lint, documented exceptions and official remediation links; no silent skipped source |
| M8 | Repository and CI stay small and reproducible | Dependency/task ownership in Mainboard, generated/vendor exclusions, deleted obsolete targets/resources, local passing receipts and authorized publication before hosted CI claims |

## Target architecture

Keep the existing four shared modules. Do not create parallel iOS/macOS feature folders or duplicate view models.

| Location | Responsibility |
| --- | --- |
| `App/UsagiUnagiApp.swift` and `App/Application` | App identity, one service graph, scene lifecycle, entitlements and platform composition |
| `Shared/Sources/StudyCore` | Sendable domain values, grading, kana/session policy, API contracts and deterministic statistics |
| `Shared/Sources/StudyPersistence` | SwiftData models, actor-owned queries/transactions, outbox/recovery, typed export and isolated read-only migration |
| `Shared/Sources/StudyUI` | Shared SwiftUI features and Observation state; narrow UI bridges live beside the feature that requires them |
| `Shared/Sources/StudySpeech` | Speech/recording lifecycle and typed transcripts; grading remains in StudyCore |
| `Resources` | Required assets, licensed reference catalogs and genuine offline fixtures; development generators use Mainboard |
| `Docs` | This specification, current task ledger, architecture decisions and scoped validation receipts |

Adapt layout to window size, content, accessibility and native presentation. Use compile-time platform checks for APIs that actually differ: microphone/audio session policy, WatchConnectivity, system settings, background refresh and window/menu configuration. A separate operating-system check must not create a second lesson/review implementation.

## Persistence contract

### Ownership and transactions

Use one model-container/actor owner for a store. ModelContext and live model objects do not escape that executor. UI, intents and future model tools receive immutable Sendable values or stable identifiers. Network requests and account verification run outside save transactions. Recheck account identity, generation and expected revision after suspension before committing.

A graded answer and the corresponding session advance/outbox record must commit together. A crash may leave the prior question or a fully committed new state; it must not lose an answer or duplicate an upload. Mark an attempt durably before sending. A timeout or uncertain server result stays pending for explicit reconciliation; it is never automatically replayed just because the process restarted. A successful WaniKani response and local acknowledgement remove work only for the matching revision. Material conflicts retain the local note and original revision until the person chooses a resolution.

Logout, token replacement, account switching and vacation must cancel or invalidate the relevant work, preserve unresolved data for the correct account and prevent an old task publishing into the new account. Multiple windows share the same store owner and cannot create competing writers.

### Schema and Codable values

Create a named VersionedSchema and SchemaMigrationPlan before the next stored-schema change. Preserve identifiers and outbox semantics during migration. Test opening a store written by the current committed app; an empty new store is insufficient evidence.

| Data | Model/query requirement |
| --- | --- |
| Account/profile | Stable verified account identity; token fingerprint where needed, never the token; account-scoped preferences/state |
| Catalog | Subject identity, level and searchable/groupable fields as model attributes; exact typed subject content retained |
| Assignments/progress | Queryable account, subject, due date and SRS state where measured hot paths need them; recent mistakes retain timestamps without inventing review events |
| Active session | Selected items, policy/options and revision preserved; transient text remains scoped to the matching window/session/question |
| Review/material outbox | Original payload, identity, revision, attempt marker and recovery/conflict information preserved atomically |
| Import receipt | Source identity/digest, verified destination and completed handoff phases retained durably |
| Statistics | Deterministic projections of saved verified progress; no independent authoritative progress copy |

The store already uses `@Attribute(.codable)`. Keep it for opaque payloads that the app does not filter or sort inside. Promote only genuinely queried fields into the schema; add indices after measuring the relevant query. Codable payload shape changes require explicit decoding compatibility and are not automatically handled as model-schema migrations. Do not normalize every nested type merely to make the diagram more relational.

### Observation

Replace custom event plumbing with ResultsObserver only after a prototype proves equivalent behavior. Keep observation on the owning actor and convert results to Sendable projections there. Check local writes, second-context commits, rollback, deletion, cancellation, logout, account changes and reopening. A rollback must not announce a committed state. Observers must not retain dead windows or publish an old account’s data.

Evaluate HistoryObserver for actual external/context writers and restart catch-up. Persist history tokens where needed, filter authors, process each transaction idempotently and test replay after a crash. A history notification wakes reconciliation; it is not proof that WaniKani accepted an answer. Avoid adding both observers and the old listeners indefinitely: delete the replaced path once parity is proven.

Apple documents [ResultsObserver](https://developer.apple.com/documentation/swiftdata/resultsobserver) and [HistoryObserver](https://developer.apple.com/documentation/swiftdata/historyobserver) in the 27 releases. [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor) already existed in earlier systems and does not make logical races across suspension impossible. The [official SwiftData session](https://developer.apple.com/videos/play/wwdc2026/274/) covers Codable limits, sectioned queries and observation.

## Migration and deletion sequence

Each phase is a reviewable checkpoint. Commit after its gate passes; no phase claims completion from a build alone. Preserve unrelated owner edits. Do not combine broad deletion, a schema rewrite and UI redesign into the same checkpoint.

| Phase | Change | Required gate before proceeding |
| --- | --- | --- |
| P0 Rules and inventory | Finish current-toolchain Swift parsing, correctness/formatting checks, migration signals, official guidance and an exact caller/dependency inventory | Real app scan covers all selected source; positive/negative rule tests; no source skipped silently; required CI commands work standalone |
| P1a Isolate legacy source location | Extract the database URL locator from LocalCachingClient; document the remaining import-only boundary | Clean install and old-install bootstrap/reopen preserve exact source discovery without constructing the old writer |
| P1b Native typed diagnostics | Replace the native SQLite backup with a consistent SwiftData export; retire old-host export with its final caller | Complete export without credentials during concurrent saves; cancellation/failure leaves the store intact. This is required for removing feature SQL, not technically for removing FMDB |
| P2 Native recent mistakes | Move cross-device timestamp merge and lifecycle ownership to native services | Fake cloud store tests for account isolation, latest timestamp, 24-hour window, malformed archives, startup catch-up, logout, simultaneous local/cloud changes and no feedback loop; native practice counts update without review uploads |
| P3 Retire legacy acceptance and UI owners | Port remaining feedback/milestone, details/conflict, login/account, Home/catalog, practice/voice, settings/audio and refresh cases to the production scene | Equivalent behavior cases on native Mac/iPhone/iPad, with local synthetic services; production routes never construct the legacy host |
| P4 Delete FMDB and old writer | Remove LocalCachingClient, PendingUploadStore, SyncStore, old TKMServices/controller callers, FMDB helpers and obsolete generated storyboard accessors/resources once their final callers are gone | Zero app-owned FMDB import/reference/dependency/linked product; current-store/historical-source migration and crash/restart gates pass; all required builds/tests pass |
| P5 Evolve native schema and queries | Add versioned migration, measured query fields/indices and sectioned projections | Before/after queue/count/chart equality, current-store upgrade, full-catalog performance comparison, rollback/recovery, no duplicate durable source of truth |
| P6 Simplify observation and services | Adopt native observers where they replace existing work; finish native watch/notification/background integration | No duplicate wake/upload loop, no stale-account publication; automated lifecycle checks plus required physical delivery/expiration evidence |
| P7 Read-only intents and AI tools | Expose bounded typed search/focus/coverage/forecast queries through explicit adapters | No credential/raw ModelContext exposure; availability fallback, cancellation, bounded queries and no ability to grade/send/acknowledge answers |
| P8 Repository and release gate | Remove unused files/dependencies/targets and finish Swift 6 mode for app-owned code; verify standalone Actions and distribution configuration | Clean checkout dependency restore, native Release builds, full automated gates, signed-upgrade/device acceptance; publish only after explicit push/distribution authorization |

P1a, P1b and P2 may progress independently after P0. P3 can progress alongside them. P4 requires P1a, P2 and P3 to pass; it cannot be replaced by marking old files DEBUG-only or renaming a wrapper around FMDB. P1b is independent of the FMDB dependency and remains necessary for M2’s removal of feature SQL. P5 must not destroy the source/import evidence still needed by supported installations. Voice usability, statistics calibration and native watch work can run independently while these storage phases proceed.

### FMDB caller and dependency removal

The current direct imports are four runtime adapters (`LocalCachingClient`, `PendingUploadStore`, `SyncStore`, `FMDatabase+Assert`) and three hosted-test files. No app-owned Objective-C implementation/header files remain tracked; Objective-C still arrives through installed dependencies. A source-extension count alone cannot establish a Swift-only built product.

| Caller or dependency | Replacement or removal condition |
| --- | --- |
| `StudyApplicationOwner` → `LocalCachingClient.databaseUrl()` | Extract the original source location into a small read-only locator; preserve exact path/default fallback behavior |
| DEBUG Screenshotter/AppDelegate/TKMServices/legacy coordinator | Move its remaining acceptance callers to injected production services before deleting the host and its controllers |
| `LegacyStudyImporterTest` | Replace its FMDatabase-based fixture writer with a system SQLite3 fixture writer; preserve all nine existing importer test functions and their malformed/WAL/schema cases |
| `PendingUploadAcknowledgementTest` and `SyncStoreTest` | Map their four plus fifteen test functions to native outbox/synchronization invariants, verify the replacements, then delete the old writer-specific tests |
| Native `SQLiteDiagnosticArchive` and old diagnostic screen | Native export currently copies `study.store`; the old host exports `local-cache.db`. Cover both responsibilities during transition, then retire old-host export with its last caller |
| Podfile and Podfile.lock | Remove FMDB, restore locked integration and inspect the resolved dependency graph; avoid unrelated dependency updates |
| Project/framework integration | Remove stale FMDB build/link/embed references and verify each destination’s linked product; retain required remaining CocoaPods integration until its other callers retire |
| SQLite3/protobuf legacy reader | Preserve its supported source conversion independently of FMDB; it already has no FMDB import |

FMDB removal does not by itself retire Reachability, SwiftGen, Hippolyte, SVGKit or their transitive dependencies. Audit each final caller separately, then remove the dependency and stale build resources at the same checkpoint. Keep source licenses and historical receipts.

### Original-data handoff and recovery

1. Open the old source read-only, including committed WAL state, and identify its supported schema and account.
2. Capture immutable source bytes/metadata and validate grading inputs, pending work, notes and progress. Do not call Settings getters that mutate old defaults.
3. Verify the destination account using the existing read-only account capability. Do not place the API token in a receipt, fixture, export or log.
4. Import all related records and a source receipt in one native transaction. A repeated import must not recreate consumed pending work. Preserve the existing conservative rule: imported pending reviews are marked attempted and pending notes uncertain because the old queue cannot prove delivery. Import must not make them automatically uploadable.
5. Save/verify credentials and activate the native-writer choice through the existing recoverable handoff sequence. Resume from durable phase state after interruption.
6. Hydrate only absent native preferences; later native edits win. Keep compatible media directories where possible.
7. Reopen in another process, verify counts/revisions/payloads and exercise one synthetic offline review and material change.
8. Keep the original source on error. Unsupported or malformed data opens recovery UI and must not silently create an empty replacement account or restart the old writer after native activation.

Signed Keychain/upgrades remain a physical acceptance gate even when disposable fixture handoffs pass. Historical source schemas 9–15 and interrupted WAL/protobuf cases must remain supported by tests until an explicit supported-upgrade policy replaces them.

## UI parity and platform exceptions

The following are the remaining boundaries to inspect, not authorization to remove their behavior:

| Boundary | Why it currently exists | Condition for removal |
| --- | --- | --- |
| StudyAnswerInput’s iOS UITextField adapter | Japanese keyboard selection, marked text, caret and return handling; Mac uses SwiftUI TextField behind the same interface | A documented SwiftUI equivalent passes physical Japanese IME/caret tests and all typed/voice/pause flows |
| UIKit/AppKit settings and lifecycle calls | OS settings, app/background capabilities and native menus/windows differ | Replace with an equivalent supported API, retaining capability behavior and errors; keep a small adapter when needed |
| Read-only legacy SQLite3 importer | Existing files use a custom schema, not a SwiftData model store | All supported original installations have a supported conversion route; never remove it by deleting user data |
| WatchConnectivity/remaining companion code | Transport and OS callbacks are not presentation | Shared native source/transport tests and paired-device delivery pass; move presentation to SwiftUI/WidgetKit separately |
| Speech/audio/Keychain system APIs | Recording, playback, secure credentials and permissions are platform services | Prefer Apple-native services; these responsibilities do not become SwiftUI views |

Use one review toolbar, answer component, results view and settings owner. Preserve keyboard shortcuts, accessibility labels, focus and draft identity. Verify compact/landscape iPhone, iPad rotation/multitasking and resizable Mac windows. Keep primary actions clear and stable; avoid additional card systems, decorative gradients, custom UI fonts or a divergent Mac dashboard. Japanese subject-font choices remain an existing study feature.

## Rules and agent guidance

Mainboard rules must distinguish facts from design judgment. Objective-C files, explicit UIKit/AppKit imports or symbols, representables, @objc exposure and SQLite3/FMDB imports produce reviewable migration signals with source positions and official references. They do not prove that every bridge is removable. Modern SwiftUI checks cover state ownership, avoidable direct type erasure, legacy navigation and observable-model migration where syntax supports a precise finding.

Use the selected Swift toolchain’s parser for current syntax. Missing tooling, parse failures or unexamined source must be visible and must not produce a clean result. Generated/vendored source is excluded explicitly. The compiler remains the authority for names, types, isolation and availability; syntax rules must not pretend to resolve those facts.

`mainboard analyze explain RULE --json` supplies offline remediation and official documentation links. Agents may consult current Apple documentation for the installed SDK, then make a small verified change. Do not send source, account data or credentials to documentation searches. Keep one formatter, the toolchain’s swift-format, plus complementary SwiftLint correctness checks. Add no competing formatter or broad baseline that hides new problems.

Automatic fixes are restricted to verified mechanical changes. Access-control edits may affect initializers; ObservableObject migration changes ownership/notification semantics; navigation changes affect restoration; persistence changes affect data. These require review and acceptance, not blind autofix. A required platform exception records its exact file, capability, reason and replacement test. Test/mock injection stays outside Release behavior and uses the real feature implementation.

## Validation and completion

| Area | Required evidence |
| --- | --- |
| Domain | Existing grading/kana/session policy, wrong/near answers, correction/defer, review order/caps, lesson selection and vocabulary exclusion |
| Storage | Atomic commits, account isolation, all historical imports, current-native schema upgrade, malformed data, rollback, interrupted migration and separate-process reopening |
| Sync/recovery | Offline completion, partial failures, rate limits, cancellation, token/account changes, material conflict and uncertain-result no-replay behavior |
| Native UI | Typed/Anki/voice entry, lessons and quizzes, results/details, settings/media, focus/drafts, Home/catalog/statistics and cold/warm links on Mac/iPhone/iPad |
| Physical systems | Japanese IME/caret, speech models/permissions/latency, audio routes/interruption, signed Keychain upgrades, notification/background expiration and paired watch delivery |
| Tooling | Rule positive/negative/shadow/comment/string cases, parser current-syntax cases, no-network lint after setup, missing-tool failure and installer checksum/timeout/atomicity tests |
| Repository | Precise before/after production LOC and dependency counts; moved/generated/test files reported separately; no orphan references/resources/targets; licenses and required assets retained |

Run through Mainboard with bounded timeouts and source-specific receipts. GUI/simulator tests run sequentially. Capture only the app window. Use synthetic injected accounts for exercises; the real WaniKani account/browser is read-only. Shared pure tests/builds may run independently with separate caches. A build pass is not a physical-device pass, a syntax audit is not a typecheck, and a local workflow is not a hosted Actions pass.

The FMDB phase is done only when source, dependency graph and built products are free of FMDB and preserved functionality passes its gates. The overall modernization is done only when M1–M8 and the outstanding voice/statistics/platform acceptance rows in TASKS are satisfied. iPhone Duo remains deferred. The dismissed Coverage popup is not reopened as an investigation.
