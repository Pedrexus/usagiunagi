# One shared codebase

The current implementation uses one SwiftUI app, `App/UsagiUnagiApp.swift`, for iPhone, iPad and native Mac. `App/UsagiUnagi.xcodeproj` has one multiplatform app scheme. Catalyst and the iPad compatibility destination are disabled. The main app, shared package and retained watch targets use Swift 6 language mode with the Xcode 27 / Swift 6.4 toolchain.

The latest implementation is **not yet validated**. The owner requested production changes first, then comparison with the original Tsurukame, then tests. Historical receipts apply only to their recorded commits. [Current tasks](TASKS.md) track unfinished acceptance; [the migration specification](Migration.md) defines storage and account-safety contracts.

| Location | Responsibility |
| --- | --- |
| `Shared/Sources/StudyCore` | Sendable domain values, grading, kana conversion, session policy, preferences, API transport, immutable reference catalogs, coverage and forecast calculations |
| `Shared/Sources/StudyPersistence` | One SwiftData actor, transactions, account isolation, sessions, durable upload outbox, recovery, refresh and legacy handoff |
| `Shared/Sources/StudySpeech` | Actor-owned Apple capture, on-device transcription, model availability and confirmed transcripts |
| `Shared/Sources/StudyUI` | Shared SwiftUI navigation/screens, Charts, observable feature owners and small Apple service adapters |
| `App/Application` | App composition, startup, scene/background ownership and cold archived-preference conversion |
| `App/LegacyStudyImporter.swift`, `App/WaniKaniAPI` | Read-only schema 9–15 SQLite/protobuf conversion; no network client or normal application writer |
| `App/Configuration` | Platform entitlements and project configuration |
| `App/ComplicationExtension`, `WatchHelper.swift` | SwiftUI watch settings, immutable cached status, native packet ownership and the transitional face provider |

## Ownership and storage

`StudyApplicationOwner`, held in SwiftUI state, coalesces startup before publishing services. `StudyAppAssembly` supplies the same account model, persistence actor, font/audio libraries, notification owner, subject/lesson settings, image caches and voice factory to every route. Windows share services rather than constructing another writer.

`StudyAppModel` owns account restoration, refresh, cancellation and observable account state. `StudyStore` commits decisions, completed submissions, notes and outbox changes atomically. Pausing a screen preserves its durable session; scene storage holds only transient answer drafts. The network layer distinguishes unsent work, attempted requests with uncertain replies, acknowledged work and explicit recovery. It never silently replays an uncertain answer or clears saved work on an error.

iOS cold import reads the original database through SQLite3 in a read-only transaction, verifies stable account identity and persists an idempotent handoff before activating native services. Archived preference metadata/decoding is independent of the removed Settings UI and does not write defaults while reading. Original databases, media and credential compatibility are preserved. Regular application writes use SwiftData; the old FMDB writer and raw SQL diagnostic export have no production caller and are retired.

Production startup now uses the owner-approved generation opener. It preserves a read-only source image, validates a separate candidate against physical schema metadata and complete values, durably selects that candidate, and retains its actor/lease for service ownership. The ten V1 model declarations preserve their original identities. Handoff values use typed equality so unordered preference Sets cannot falsely reject an equivalent store; session/catalog order stays significant. Canonical Mac/iOS compilation passes, but runtime migration and G7 remain unverified. Historical nested decoders still need independent freezing before a V2/property change. See the [implementation checkpoint](Implementation/2026-10-20-native-store-opening.md) and [migration specification](Migration.md).

## Study experience

`StudyRootView` owns one typed navigation stack and the Home, Practice and Statistics destinations. Review, lesson, catalog and settings behavior lives in shared views. WaniKani subject colors, system text styles, SF Symbols and native glass controls remain the visual basis. Layout adapts to available space; platform conditions belong at capability boundaries.

Reviews and extra study use the same grader/session engine. Native review actions include typed/Anki grading, correction, adding a meaning synonym with the corresponding correction in one transaction, exclusion, defer, wrap-up, previous-subject details and completed-subject summaries. Continuing after an incorrect answer can advance without revealing it. Ending early retains the completed-item summary while discarding unfinished session work. Character-specific soft errors use the grader's exact normalized UTF-16 ranges in a SwiftUI attributed-text hint. Physical input and keyboard shortcuts still need final acceptance.

Command-C and Command-A retain system Copy/Select All behavior; correction actions use Control-C/Control-A. Font actions preserve ordinary Tab and arrow-key focus/caret behavior. These intentional shortcut changes must be included in the original-app usability comparison.

Voice views receive an app-owned capture factory. Opening Voice starts listening without another Start tap; unavailable models still require an explicit download. Recognition produces a reviewable transcript; reading answers containing kanji require explicit kana correction. Voice never changes the grading policy. Capture cleanup and a shared audio lease prevent recording/autoplay conflicts across windows. Physical microphones, speech models, latency, interruptions and audio routes remain device gates.

`SessionSummaryView` counts completed subjects, using each meaning/reading's first result. Missed items reopen shared subject details. Subject details use the shared original-conjugation vocabulary highlighter, optional attributed mnemonic artwork, hidden/locked-subject filtering and one revision-checked material editor. Font/audio catalogs and caches have one owner; shared default adapters preserve imported settings and media paths.

Statistics use Swift Charts for coverage, SRS and pace/focus scenarios with chronological backtesting. The bundled reference catalog includes cumulative Kanji Kentei levels 10–2 (including pre-2), school/Jōyō sets and estimated JLPT sets. Provenance and generation rules live in [resource sources](../Shared/Sources/StudyCore/Resources/SOURCES.md). Coverage is a character-scope measure, not an exam pass probability.

## Cross-device and platform services

Recent mistakes remain durable locally. One optional app-owned `StudyMistakeSync` projects the last 24 hours to Apple key-value storage as practice hints, fences observed account/quota/initial events, and performs bounded foreground reconciliation. Verified historical username binding/revocation is persisted in the existing handoff payload. KVS provides neither an atomic cross-device merge nor remote acknowledgement. Proper owner-controlled signing and a shared iOS/Mac namespace remain open; no signed delivery is claimed.

`StudyNotifications` and `StudyCompanionDelivery` read one typed account projection. Notification preference/permission intent is separate from delivery. The watch adapter retains the original packet keys, activation retry, latest pending absolute schedule and duplicate window. iOS background refresh uses Apple's asynchronous task-request API; a background or fixture launch does not request permission.

The watch settings and WidgetKit complications use SwiftUI. Reviews/Level remain a single global choice; the historical unavailable selection 2 is preserved. `WatchCompanionCache` retains the installed extension's `LastKnownData`/`DataSource` defaults and atomically mirrors one typed binary property-list snapshot into an App Group. The widget reads that file without starting transport or accessing the account store. Startup, accepted packets, selection changes and face migration publish before requesting a WidgetCenter reload. Connectivity background tasks stay retained through activation, pending-content drain and queued main-actor publication attempts. Count projections accumulate independent hourly buckets and expire at the existing deadline; they assume no subsequent reviews.

The watch retains Apple's documented incremental `WKHostingController` path. The existing WatchKit extension product inherits `_WKExtensionMain`; availability of SwiftUI `App` and `WKApplicationDelegateAdaptor` alone does not establish its launch handoff. The current Apple workout sample has already converted its active target to an application, so it is not proof for changing this extension's linker settings. No speculative entry-point, bundle-identity or container migration is applied. The [watch checkpoint](Implementation/2026-10-20-watch-swiftui.json) records the source and SDK evidence.

## Remaining non-SwiftUI boundaries

- The iOS Japanese answer field is a narrow UIKit adapter for keyboard-language selection, marked text, selection and caret behavior. It is not a second study screen. Removal requires equivalent native SwiftUI input behavior on physical devices.
- Image decoding, AVAudioSession, Keychain, notifications, background scheduling and WatchConnectivity are platform service APIs used by SwiftUI. Their platform-specific setup remains necessary.
- Radical SVG display uses Apple's SwiftUI WebView and the shared cached source. The SVGKit dependency is removed.
- The watch settings screen retains the three-line `WKHostingController` adapter and empty 18-line scene for its installed extension/defaults identity. WidgetKit owns complication rendering in all four accessory families; the original ClockKit class now only migrates installed faces. Shared-container access, signed face upgrades and physical delivery remain unvalidated. The final single-target watch lifecycle conversion is separate. The main iPhone/iPad/Mac app has no storyboard/controller host. See the [WidgetKit checkpoint](Implementation/2026-10-20-widgetkit.md).
- Historical account conversion still needs SQLite3 and generated Swift protobuf messages. These decode old files; SwiftData cannot directly interpret the original custom schema.

The old DEBUG UIKit host, duplicate controllers, fifteen iOS storyboards, generated navigation/assets wrappers, FMDB and associated dependency integration are being retired together. Three preexisting owner-edited legacy files remain untouched on disk and are excluded from targets. Old test sources still need their final-stage ports. No pass or final LOC/dependency acceptance follows from source deletion alone.

## Developer workflow

Mainboard owns dependency restoration, bounded Xcode operations, results/diagnostics, formatting, lint, Swift syntax rules and per-file source inventory. There is no app-local build driver. `mainboard analyze swift-inventory` reports physical/nonblank lines, source classifications, imports, platform conditions and placed migration signals; it does not infer target membership or safe deletion. CocoaPods/SwiftGen integration is removed; native Swift packages retain committed resolution.

Apple execution now retains readable JSON diagnostics beside each exact result bundle, including failed native runs. `analyze swift-compare` compares saved source inventories with category changes separate from byte changes. These reuse Mainboard's typed reports and atomic generated-file writer; routine edits use direct patches and existing formatters. Neither feature authenticates a supplied inventory or proves the compiler's exact source inputs. See the [workflow checkpoint](Implementation/2026-10-20-mainboard-reports.md).

Synthetic services remain in DEBUG-only acceptance fixtures, isolated from real credentials/cloud/permissions. XCTest remains appropriate for UI automation; domain and persistence tests use Swift Testing. Final work proceeds through implementation completion, original-app usability comparison, then test/Release/dependency/runtime gates. The detailed former adapter descriptions remain in Git at `4842707d`; immutable [validation receipts](Validation) retain their exact historical scope.
