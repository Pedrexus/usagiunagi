# SwiftUI migration study

Audited 2026-10-17 against this fork and the installed Xcode 27.0 / Swift 6.4 toolchain. This is a migration plan, not a claim that the app is already entirely SwiftUI. The iPhone/iPad app now targets iOS/iPadOS 27.0. The new native Mac target requires macOS 27.0. The shared StudyKit package and Mac app use Swift 6 language mode; the remaining legacy iOS app uses Swift 5 mode.

## Recommendation

Move the application UI to SwiftUI in small, working slices. Use Swift for app-owned logic. Retain a narrow UIKit input adapter until the Japanese keyboard and composition behavior have an equivalent implementation. Preserve existing data and grading semantics. The latest user direction prioritizes SwiftUI presentation; continue the shared SwiftData/async URLSession cutover without expanding legacy storage infrastructure, retaining the working database until a verified import and cutover is ready.

SwiftUI is a UI framework, not a replacement for networking, persistence, speech recognition or data-generation tools. A repository containing several languages does not mean its screens use several competing UI frameworks. Rewriting generated or build-time code solely to improve GitHub's language percentages would add risk without simplifying the app people use.

Apple explicitly supports incremental integration in [Modernize your UIKit app](https://developer.apple.com/videos/play/wwdc2026/272/). Statistics now uses shared SwiftUI views and Apple Swift Charts hosted in the existing iOS tab controller and a native macOS NavigationSplitView. Its Swift 6 calculations, curriculum data, native API client and SwiftData store are in StudyKit, with tests.

## Swift 6.4 and SwiftUI 27 audit — 2026-10-17

Checked the installed Xcode 27.0 (27A266a), Apple Swift 6.4 compiler and SDK declarations against the [Swift 6.4 release notes](https://www.swift.org/blog/swift-6.4-released/), [Swift 6.2 concurrency changes](https://www.swift.org/blog/swift-6.2-released/), [Swift 6.3 release notes](https://www.swift.org/blog/swift-6.3-released/) and [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui). Compiler version, language mode and SDK version are separate: Swift 6.4 still uses Swift 6 language mode (`.v6` / `SWIFT_VERSION = 6.0`). The legacy iOS target remains Swift 5 until its concurrency violations are resolved.

### Adopted in this checkpoint

- Raised StudyKit's minimum tools version to 6.4. Its production targets require explicit existential `any` types and opt into caller-isolated nonisolated async functions. StudyUI defaults to MainActor; domain values and persistence retain their own isolation. The test targets intentionally remain ordinary Swift 6 consumers to catch public API incompatibilities across compiler settings.
- Added explicit `@concurrent` boundaries to bulk snapshot processing and the transport/JSON request helper. Otherwise the new async default could move expensive decoding onto the caller's UI or database actor. A regression test calls from MainActor and checks that synchronous decoding leaves the main thread. Network errors and cancellation remain untyped `throws`: collapsing them into an API-only error would hide whether a write may have reached the server. Pure kind/timestamp validation uses `throws(APIError)`.
- Replaced HTTP method strings with a closed enum, and Mac sidebar strings with a destination enum. Kept generic view composition and Sendable value models. The voice protocol now exports one callback type: its async isolation semantics no longer depend on the importing app's language/feature flags. This caught and fixed both the test actor and the Swift 5 screenshot host during compilation.
- Used `@Bindable` for review presentation bindings and `@ObservationIgnored` for task handles/internal bookkeeping. The [new State macro](https://developer.apple.com/documentation/swiftui/state()) is selected by Xcode 27 for declaration-initialized state; the Mac app's owned observable store already uses that form. Injected voice controllers still deliberately keep their existing per-panel lifetime.
- Replaced the artwork cell's `AnyView`, retained hosting controller, manual constraints and first-window/UIScreen dimensions with `UIHostingConfiguration` and an ordinary SwiftUI view. It uses the iOS 27 [AsyncImage request initializer](https://developer.apple.com/documentation/swiftui/asyncimage/init(request:scale:transaction:content:)) with native HTTP cache policy. Content fits the cell width, and system styling replaces the hard-coded white card/shadow. This is HTTP caching, not a completed offline-media feature; the current parent still hides artwork when offline.
- Removed the unnecessary Speech `@preconcurrency` import. The AVFoundation import still needs a documented compatibility boundary: SDK 27's `AVCaptureSession` is not Sendable when passed as NotificationCenter's sender filter. App-owned capture/session mutations remain on the capture actor. No new `@unchecked Sendable` conformance was added.

### APIs to use when their feature slice is migrated

| Capability | Application decision |
| --- | --- |
| SwiftUI 27 `ArrangementView` and split sizing | Evaluate for question/details and lesson layouts across resizable iPad/Mac windows. Preserve keyboard/focus behavior before replacing the already-tested review layout. Duo-specific hinge/reserved-region work stays deferred. |
| SwiftUI 27 item/error dialogs and toolbar overflow/priority | Use for forthcoming upload recovery and account errors: represent the selected recovery issue as one optional item rather than parallel booleans/payloads. Keep primary review controls visible. |
| SwiftUI 27 unified content builders and state initialization | Let the compiler provide the new behavior where applicable. Keep generic `some View` components; avoid `AnyView` and wrapper protocols with one implementation. No need for a custom observation/event-bus layer. |
| Swift 6.4 async defer and cancellation shields | Consider for asynchronous resource cleanup when it replaces duplicated paths. Do not shield account-bound uploads from cancellation or delay account-switch fencing just to use these features. |
| Swift 6.4 observation tracking APIs | SwiftUI already tracks the properties read by a view. Explicit tracking is only useful for a demonstrated non-view observer; none is needed for these forms. |
| Swift 6.3 C exports, module selectors and specialization | No new C export boundary or ambiguous imported symbol needs these APIs. Keep the read-only SQLite importer narrow; avoid forced inlining/specialization until a measured hot path justifies binary-size tradeoffs. |
| Swift 6.4 borrowing collections / `UniqueArray`, `Span`, `InlineArray` | Profile the grader/catalog first. Existing variable-sized Codable arrays and the rolling-row distance algorithm do not justify ownership-heavy replacements. |
| SwiftData native Codable attributes, queries/history | Already adopted for typed persistence. Add native queries/observation during screen cutover; local history cannot establish remote-upload success. |

### Abstraction and typing follow-through

Keep the shared `CatalogSubject` as the complete native content model. `GradingSubject` and the compact statistics snapshot are purpose-specific projections; they should be derived at boundaries, not become competing writable repositories. The native API now derives statistics snapshots from the complete catalog decoder and downloads all offline study categories together. Keep that single decoding path rather than introducing another generic repository/service hierarchy. The existing injectable transport closure is enough for deterministic API tests.

Raw subject/assignment IDs and numeric SRS stages remain in persisted/API compatibility models. Validate them at import/write boundaries. If mixed-ID defects appear, introduce small nominal IDs with explicitly compatible Codable representation, then prove old-store import/reopen parity; changing every persisted scalar now would increase migration work without demonstrated benefit. SwiftData model references must remain on their model actor; return immutable Sendable snapshots across actors.

The complete-concurrency diagnostic pass observed **412 distinct non-vendored warning locations/messages** across its build and test runs: 262 production, 95 generated, 53 UI-test/tooling, and 2 watch. This is an observed incremental-build inventory, not a clean whole-graph count or 412 independent bugs. Major sources are archived static settings, table/delegate actor contracts, storyboard-generated factories, notification callbacks, audio and legacy caching. The successful final iOS test run alone reported 349 of those. Enabling Swift 6 on the entire legacy target would turn many into errors; do not silence them with blanket preconcurrency imports or unchecked conformance. Migrate settings to native preference ownership, annotate genuine UI protocols/factories on MainActor, finish the actor-backed repository, and remove obsolete generated layers as their callers move. CORE, SETTINGS, SYNC, DEPEND and WATCH retain those gates in TASKS.md.

No feature was disabled for this audit. UIKit keyboard/composition and navigation/service adapters remain until parity is demonstrated; rich details and iOS font-library presentation now use shared SwiftUI. System SQLite and SwiftProtobuf remain read-only legacy-format compatibility code; Speech/AVFoundation, URLSession and SwiftData remain the native non-UI services.

## What is actually in this repository

| Area | Current implementation | Proposed treatment |
| --- | --- | --- |
| Screens and navigation | Shared SwiftUI reviews, lessons, statistics and catalog; native SwiftUI iOS main settings. The current app-owned tree has 21 storyboards and 6 XIBs, including thin hosting scenes, launch screens and auxiliary/watch targets. | Finish Home/login/download/developer presentation and the app shell; remove each obsolete layout/accessor after its callers migrate. |
| Home and statistics | Custom table models and UIKit drawing; new SwiftUI statistics screen | Native `List`, `Section`, `Label`, `Button`, `TabView`, `NavigationStack`, semantic colors and system fonts. Keep study-specific Japanese font settings. |
| Charts | Statistics uses Apple Swift Charts; the unused third-party Charts 4.1 dependency was removed | Migrate the remaining legacy upcoming-review drawing with its parent Home screen. |
| Input | Shared Swift `KanaConverter`, Swift `TKMKanaInput`/`AnswerTextField`, keyboard overrides | Objective-C conversion removed after 86,210 full-string and 11,392 interactive comparisons. Keep the narrow native adapter for selection/composition and later wrap it in `UIViewRepresentable`; physical input-method checks remain open. The review screen now hosts this input through `UIViewRepresentable`. |
| Grading | Shared Swift `AnswerGrader`/`GradingSubject`/`AnswerDistance`; thin iOS protobuf adapter | Full grader moved into StudyCore; 292,880 grade categories and 18,225 distance results compared with the original. Unicode highlight offsets fixed. Session/voice integration reuses this engine. |
| Review sessions | Shared Swift `StudySession`, SwiftUI `ReviewScreen` and shared rich subject details, hosted by an iOS repository/navigation adapter | The old review layout, constraints, waves, details table and custom success-animation implementation are removed. Native Mac reviews use the atomic session/outbox boundary. The iOS input and cache/session owner remain temporary adapters; durable restoration/caller cutover and full mode parity remain. |
| Offline storage | FMDB / SQLite, protobuf blobs, pending review and study-material queues | Full refresh retains offline snapshots until complete responses arrive; revision-aware transaction-level merges protect pending notes and local review progress, including local changes acknowledged while a download is in flight. Additive schema 14/15 migrations preserve existing payloads. Download callbacks honor reset/logout lifetimes. Migrate to a shared SwiftData repository with typed models, actor isolation and explicit transaction boundaries. The production StudyPersistence store verifies atomic session/answer persistence, rollback, conditional acknowledgement, note merges and separate-process recovery. Mac cache callers have switched to it, with a one-time credential-bound JSON importer. The iOS database/callers have not switched yet. SwiftData does not import this legacy schema automatically: validate a one-time import and rollback path before switching callers, then remove FMDB and replaced wrappers. Do not maintain two permanent writable stores. |
| Async/networking | Shared Swift 6 upload actor; legacy PromiseKit API/downloads, URLSession, Reachability | Immediate/background writes share one process-wide lane and reload current durable payloads. An adapter currently bridges the legacy client to async/await. Replace PromiseKit chains with URLSession async APIs and structured concurrency, deleting the replaced adapter paths. Keep WaniKani-specific response validation, rate-limit handling and account ownership; rejected/ambiguous review reconciliation remains open. Network path status is advisory, not proof a request will succeed. |
| Review quick settings | Shared SwiftUI form in native iOS/Mac sheets; SwiftUI end/wrap-up confirmation | MMDrawerController, its Objective-C hook and the drawer-specific menu controllers are removed. iOS archived preference keys remain; Mac uses observed AppStorage with field-wise merging. Audio and font-library implementation still await Mac migration. |
| Images | Haneke cache and SVGKit radical rendering | SwiftUI loads avatars. Native reviews render validated, locally cached SVG bytes through Apple’s SwiftUI WebView. Full offline prefetch, audio and legacy iOS SVGKit removal remain open. |
| Text matching | Rexy for POSIX longest-match behavior | Compare matching semantics before replacing it with native Regex. Similar syntax is not proof of equivalent highlighting. |
| Other languages | Go files/modules and the unused C++ SQLite inspector have been removed; similar-kanji generation now uses Swift. Ruby/Fastlane/build scripts remain. | Replace active runtime/UI callers before removing their infrastructure. Build/distribution tooling and generated output have separate requirements from SwiftUI screens. |

## Current Apple tools worth adopting

Use native controls and navigation first: the system supplies Liquid Glass where appropriate. Avoid placing glass behind every content row. The iOS 27 floor allows native Liquid Glass controls. The dashboard uses conventional content surfaces; glass belongs to navigation and controls, not every chart. See [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

For the eventual SwiftUI shell, use typed navigation destinations, narrowly scoped observable state, explicit bindings for edits, and value snapshots for read-only rows. Keep grading and statistics independent of UI state. Use `@Observable` when the deployment floor permits it, with UI ownership on the main actor and background work returning safe value types.

[What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/) introduces Xcode 27 state initialization, toolbar and image-loading improvements. Toolbar priority is useful for review controls on smaller windows; image request/session customization may replace some avatar plumbing. New document APIs are not relevant to this app. The installed SDK documentation was also checked: new image customization APIs require iOS 27 availability checks. Compiler version, language mode, SDK version and minimum supported OS are distinct choices.

Do not switch the entire project to Swift 6 mode in the UI change. The baseline already has protobuf/Sendable warnings and shared mutable services. Follow the [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/): diagnose and isolate one target at a time, update/regenerate dependencies deliberately, and avoid masking errors with unchecked Sendable declarations.

### The strict SwiftUI limitation

`AnswerTextField` overrides `textInputMode` to choose an installed Japanese keyboard. Apple's [textInputMode documentation](https://developer.apple.com/documentation/uikit/uiresponder/textinputmode) describes this UIKit capability. The reviewed [SwiftUI text-input APIs](https://developer.apple.com/documentation/swiftui/text-input-and-output) do not establish equivalent language selection. A SwiftUI `TextField` replacement must therefore demonstrate parity before removing the adapter. Test marked text, selection, deletion, paste, hardware keyboards and switching between meaning and reading questions.

### Deployment and native platforms

The requested floor is now **iOS/iPadOS 27.0**, with a separate **macOS 27.0** native app. Xcode 27.0 / Swift 6.4 is installed. iPhone portrait and landscape are enabled; SwiftUI chart layout responds to available width and Dynamic Type. iPhone Duo-specific work is deferred at the user's request.

`native/TsurukameMac.xcodeproj` builds a SwiftUI Mac app directly, without Catalyst or the iOS UIKit/CocoaPods stack. It supports account connection, manual refresh, offline statistics, curriculum charts, subject searching, rich saved subject details, local note/synonym editing and durable native reviews. Image-only radicals have on-demand caching. **Lessons, complete review options, audio, download management, notifications and full settings remain unfinished.** This does not establish feature parity; see TASKS.md for current acceptance gates.

Mac reads full study content through URLSession/async-await and commits it in the shared SwiftData store; the previous JSON cache is imported once. Credentials stay in Keychain, and a fingerprint binds each visible snapshot to its credential. Fetch failures do not publish partial snapshots. Native validated write endpoints and a durable upload lane are now implemented; the Mac Saved work screen exposes explicit synchronization of eligible locally saved work. Existing iOS review uploads and its database remain active until the controlled writer handoff. Cross-device learning progress syncs through WaniKani; app preferences, local downloads and pending reviews are not shared through iCloud.

### What prevents “pure SwiftUI” today

| Feature | Swift/SwiftUI outcome | Choice still needed |
| --- | --- | --- |
| Home, settings, catalog, review UI, lesson UI | Main review layout is shared SwiftUI; most other iOS screens still await migration | Preserve features while replacing each screen and deleting its old implementation. No need to disable them. |
| Rich review answer details and font library | Shared SwiftUI presentation behind small iOS navigation/service hosts | Rich details, note/synonym editing and the iOS font library now render in shared SwiftUI. Core Text handles font registration and URLSession handles downloads; these are native services rather than UI exceptions. Native Mac font-library integration remains open. |
| Forced Japanese keyboard selection and marked-text behavior | Needs a small UIKit text-input adapter until SwiftUI provides equivalent control | Keep the adapter, or accept system-selected keyboard language after explicit input-parity testing. |
| SVG-only radicals | SwiftUI Image does not directly replace the existing SVG renderer | Native reviews use Apple’s SwiftUI WebView with a small HTML image wrapper, disabled scripts and local SVG bytes. No app-owned UIKit/AppKit representable is needed. The legacy iOS SVGKit path remains until its callers migrate. |
| Speech recognition | Swift service using Apple's Speech framework; SwiftUI provides its controls | Shared Swift 6 capture service and SwiftUI panel feed iOS and native Mac review grading. Keep typing available; transcription cannot establish pronunciation quality. Physical microphone/model validation remains open. |
| Storage and networking | Swift actors and async APIs, not SwiftUI responsibilities | Mac reads and explicit saved-work uploads use the shared native store. Complete iOS transactional queue/caller cutover and old-data migration before removing FMDB/PromiseKit. |
| Grading and kana conversion | Can be entirely Swift | Preserve UTF-16 edit-distance/transposition semantics and kana composition behavior with parity tests. Both grading and kana conversion are now shared Swift, with direct legacy parity comparisons. The native text-input adapter remains. |
| Protobuf, SQLite engines and Apple frameworks | Swift-facing APIs may contain generated or compiled non-Swift internals | “App-owned code in Swift” is achievable; “no non-Swift code anywhere” is not a meaningful platform guarantee. |
| Watch companion and build/data utilities | Separate platform/tooling migrations | Keep current functionality; not included in the new Mac target. |

## Migration order and completion gates

1. **Stats and shared appearance (this change):** SwiftUI statistics, standard typography and symbols, native Home actions, preserved red error feedback. Build and test; inspect sample data in light/dark mode and enlarged text.
2. **Home, settings and navigation:** replace table-model screens with SwiftUI, introduce typed routes, preserve login/logout, search, vacation mode, settings persistence and deep links. Delete migrated controllers/layout files rather than keeping two permanent versions.
3. **Subject browser and details:** preserve mnemonic markup, links, synonyms, radical images, downloaded audio and font choices. Profile scrolling using a full-size account dataset.
4. **Review and lesson sessions:** the deterministic state machine and main SwiftUI review layout are implemented. Continue with durable resume, native Mac integration, lesson navigation and the remaining rich-details/settings bridges. Expand mode coverage for wrong/alternate answers, correction, interruption, queues and input behavior. Keep the small input adapter as necessary.
5. **Data and dependency cleanup:** test offline review completion, restart before upload, failed/duplicate upload responses, retry ordering, reset/vacation transitions and old-database upgrades. Only then replace FMDB/PromiseKit and remove unused dependencies. Migrate the watch companion independently.

Use Swift Testing for isolated unit/integration coverage, migrate existing XCTest suites after reviewing fixture ownership, and keep XCUITest for UI workflows. Use previews for empty, loading, offline, vacation, error and populated states, then verify actual Simulator/device behavior. Preview success is not proof of sync correctness.

Track app-owned production LOC, storyboard/XIB size, dependencies and behavior coverage separately. The Home action component shrank from 406 to 114 physical lines; the statistics feature adds code, so this change does not claim a net reduction across the whole app. Splitting a large file into smaller files alone is not a reduction.

## Voice review implementation and remaining validation

The iOS review microphone opens a shared SwiftUI form with explicit start, stop, cancel, transcript correction and keyboard fallback. `StudySpeech` owns capture and UI state in Swift 6; `VoiceAnswerDraft` accepts only final segments for one recording/question. The host checks the question token again after dismissing the sheet, then submits through the existing grading and transactional progress path. Voice is disabled during Anki self-grading and answer feedback.

The installed iOS/macOS 27 SDK provides [CaptureInputSequenceProvider](https://developer.apple.com/documentation/speech/captureinputsequenceprovider) for microphone audio into [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer). Capture runs on an actor, checks device/locale support, requests microphone access and offers an explicit speech-model download. Apple's [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) processes speech on-device. This implementation does not use the older server-backed `SFSpeechRecognizer` authorization path; see Apple's [permission guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition). Microphone purpose strings are localized; the Mac target declares its audio-input entitlement.

Stopping releases the capture provider so the [analyzer input sequence](https://developer.apple.com/documentation/speech/captureinputsequenceprovider/analyzerinputs) can end, then finalizes transcription. Cancellation, backgrounding and capture failures stop recording; a finalization timeout returns to typing. The app does not save audio. Interrupted/cancelled recordings and stale callbacks cannot submit an answer. Automated tests inject capture events; they do not establish actual microphone or model behavior.

Japanese recognition may produce kanji. The panel requires an explicit kana correction before a reading can be submitted; it does not convert recognized kanji into the expected reading or infer a pronunciation score. This limitation may reduce the speed benefit for Japanese answers. Physical-device tests must establish useful accuracy/latency and whether another speech strategy is needed. The shared panel/service compile for Mac, but the Mac app still needs its review workflow before exposing voice input.

## Recorded iOS 27 validation — 2026-10-17

The iOS and native macOS targets build with Xcode 27. The current suite has 102 shared Swift Testing functions covering curriculum, coverage, account/cache/API behavior, grading and kana, plus all 102 shared tests on iOS and 75 iOS tests for grading adapters, native kana input, existing logic and statistics. Direct legacy comparisons cover 292,880 grade cases, 18,225 edit-distance pairs, 86,210 whole-string kana conversions and 11,392 interactive edits. Manual native Mac checks passed for sample-data loading, chart display, coverage drill-down, opening a subject from a coverage gap, and subject searching. iPhone and iPad Simulator coverage layouts were also inspected. Nine distinct UI flows passed on iPhone (suite plus targeted rerun) and together on iPad: typed session completion, voice transcript/typing fallback, wrong-answer reveal/override, combined Anki, landscape typing, exact-match changes with draft preservation, font-library return, explicit end and wrap-up/stop-wrap-up. Native quick-settings sheets were visually inspected on both devices. The question, rich answer details and voice panels were visually inspected, along with the compact iPhone landscape layout. The session algorithm also matched 960 legacy scenarios across 676,404 state assertions. The upload coordinator also has controlled serialization/lifetime and SQLite in-flight-edit tests; 26 mocked legacy API-client tests validate response handling; eleven shared native-client tests cover typed writes and failures. Rejected reviews remain pending while assignment/conflict reconciliation is unfinished. These checks do not establish full feature parity. No real-account login or review upload was exercised.

## Native persistence simplification decision

The user requested a simpler Apple-native approach on 2026-10-17. Use [SwiftData](https://developer.apple.com/documentation/swiftdata/) for the local store and [URLSession async transfers](https://developer.apple.com/documentation/foundation/urlsession) for WaniKani requests. The installed SDK exposes `@ModelActor`, unique constraints and `ModelContext.transaction`; the [2026 SwiftData updates](https://developer.apple.com/documentation/updates/swiftdata) also add query sections, explicit Codable attributes and result/history observers. Adopt these where they replace real code, rather than adding abstractions solely to use new APIs.

The [standalone restart check](experiments/NativePersistenceProbe/README.md) now uses production StudyPersistence models; the duplicate prototype implementation was removed. Its write and independent-process reopen phases pass. The Mac snapshot cache has migrated to this store, while the iOS SQLite migration remains unfinished. This does not eliminate the need for WaniKani reconciliation. Do not use SwiftData history as proof that a remote request succeeded. Keep the outbox local to its submitting device; WaniKani remains the authority for study progress. CloudKit-backed app preferences can be considered independently after account semantics are clear.

Full catalog/domain models, verified native reads/uploads and the read-only iOS schema 9–15 importer are implemented and fixture-tested. Next: finish recovery and app-owned sync coordination, hand off the old writer, cut over existing callers, and remove the replaced FMDB/PromiseKit infrastructure. Preserve the existing queue, offline subjects/notes and session behavior. Compare production LOC only after replacement; test/prototype LOC is separate. The unfinished legacy recovery draft was set aside locally, and is not part of the app or an additional permanent implementation.

The shared native store persists Codable snapshots, sessions, completed submissions and study materials. Sessions enqueue only newly completed items in the same transaction and use revisions to reject stale scenes. Materials combine content and pending/revision metadata in one model. Thirty-seven dedicated persistence tests pass on both macOS and iOS; complete snapshot round trips and fresh-process durability are verified. The Mac legacy import retains the old file until explicit disconnect; import receipts prevent removed data from returning. The native reader now records stable user IDs and correctly reads vacation status. Eight iOS importer tests additionally verify SQLite-to-SwiftData reopening, all supported old schemas, pending payloads, grading inputs, radical metadata and WAL behavior without modifying the source. The one-time importer uses the system SQLite API and existing SwiftProtobuf decoder; these are data-format compatibility code, not UI bridges. The shared native API client now implements validated review/lesson/note requests, including the documented nested lesson timestamp body. Those writes now connect to a verified-account SwiftData upload lane with durable attempts, conservative issue retention, conditional acknowledgement and rate-limit delays. User-visible recovery, full download/cache/session integration and activation of the iOS migration remain open requirements.

## Complete native download and atomic refresh checkpoint

The shared reader now downloads full radical/kanji/vocabulary/kana-vocabulary content, assignments, notes/synonyms, level history, review statistics, voice metadata and subscription limits. `fetch` is a statistics projection of this download, replacing its separate abbreviated subject/assignment decoders. Mnemonics/hints, example sentences, component/similarity links, legacy-compatible MP3 references and inline SVG radical references survive into native models. Historical radical mnemonics and the similar-kanji supplement use the existing bundled datasets; their legacy copies remain only while the old API module is active. Unknown parts-of-speech labels survive alongside known legacy enum values. Optional new catalog metadata preserves old Codable stores.

Checked the [WaniKani assignment contract](https://docs.api.wanikani.com/20170710/#assignments): assignments do not include a level. Removed that erroneous decoding requirement and derive levels from the subject catalog, including successful upload responses. Tests now omit the invented field. Collection reads require valid resource IDs/type, collection envelopes, matching total counts and same-endpoint pagination; duplicate resources, missing subjects, changed identity, malformed content or failed pages prevent publication. Full reads include hidden records for reconciliation, while ordinary snapshots exclude hidden subjects/assignments. No incremental watermark is invented from wall-clock time.

`StudyStore.refresh` owns one read pass and commits catalog, assignment/material merges, account state and visible snapshots in one transaction. Local session and pending-write records survive; stale clean records can be removed, while content referenced by pending work or an active session is retained for recovery. Assignment revisions and material revisions captured before download protect concurrent edits and uploads. A note acknowledgement now changes its revision too, covering a pending edit that already existed when the download began. Pending review subjects stay out of the visible assignment list. Rejected/uncertain writes are never acknowledged by a download. Cancellation/account generation fencing and persistent account backoff apply to reads as well as writes; `cancelSynchronization` cancels and awaits both lanes before account/data transitions.

The native Mac connect/refresh path now uses this full store transaction. Subscription limits are loaded offline from account state and applied to subject browsing/detail access, as required by the [user API contract](https://docs.api.wanikani.com/20170710/#user). Older caches without verified limits remain conservative until refreshed. Statistics retain historical evidence independently of content access. Mac full detail/review/lesson UI is still unfinished; this checkpoint supplies its offline data rather than claiming feature parity. Disconnect removes the visible account snapshot and token; account-bound pending work remains in the native store.

Validation: **102 shared Swift Testing functions pass on macOS and iOS 27** (59 core, 6 speech, 37 persistence), including complete payload/hidden-data tests and eight refresh functions covering process reopen, pending notes/reviews, a half-answered session, missing resources, account mismatch, cancellation, overlapping reads, backoff and an upload racing an older download. **75 iOS app tests pass** and the Mac app builds. A separate executable built from committed `c8db161` models wrote catalog/assignment/pending-note rows; the new production store reopened them successfully after the additive assignment-revision change. The independent-process upload probe also retains uncertain attempt markers. The initial incremental iOS test directory contained stale resource copies; the full suite passes from fresh derived data. No live account was accessed.

Next gates remain explicit: recovery actions/UI for ambiguous writes; iOS adoption of shared sync ownership; incremental refresh and efficiency; recent-mistake and durable-session UI integration; atomic iOS writer handoff; native Mac study/detail UI; media downloads; removal of replaced legacy implementations. Full refresh is implemented, but the iOS app still uses its existing writer. Do not enable a second writable queue or delete the legacy database before those gates pass.

## Swift Testing, Mainboard and native formatting

The intended local workspace is `/Users/pedro/Developer/Projects`, with this standalone fork under `apps/usagiunagi`. Root `mainboard.toml` owns the task entries. Run from that root using `mainboard run --as-is <task>` to use the installed environment without changing the unrelated lock. These tasks invoke Apple's Xcode toolchain directly; Mainboard and its Python implementation are developer infrastructure, not shipped app code.

| Task | Purpose |
| --- | --- |
| `usagi-toolchain` | Show the selected Xcode/Swift versions. |
| `usagi-simulators` | Discover available simulator names, runtime IDs, UDIDs and states. |
| `usagi-resolve` | Restore Xcode Swift dependencies using the committed resolved versions. |
| `usagi-pods` | Restore legacy CocoaPods dependencies with `--deployment`. |
| `usagi-test` | Shared Swift Testing on macOS. |
| `usagi-test-ios` | Shared tests on an iOS 27 simulator. |
| `usagi-test-app` | Hosted iOS Swift Testing and remaining XCTest suites. |
| `usagi-test-ui` | Synthetic XCUITest review flows. |
| `usagi-build-mac` | Native Mac debug build with ad-hoc signing. |
| `usagi-diagnostics <path>` | Read compiler errors, warnings, source locations and build status from an exact result bundle. |
| `usagi-results <path>` | Read the exact test bundle using the selected Xcode. |
| `usagi-results-shared` / `usagi-results-app` | Read the newest shared or hosted/UI Xcode result bundle as structured evidence. |

The simulator tasks currently select the installed iPhone 18 Pro / latest runtime by name. Build/test tasks have hard timeouts and use separate derived-data locations where needed. Xcode result bundles remain under ignored build directories. The standalone fork still opens directly in Xcode; the parent workspace is not an application dependency.

[Apple's migration guidance](https://developer.apple.com/documentation/testing/migratingfromxctest) supports gradual adoption. The shared package already uses Swift Testing; four independent hosted suites now do too. Use structs and per-test fixtures, parameterized examples rather than opaque loops, `#require` for values needed by subsequent checks, and async/await for completion. The hosted target uses `SWIFT_TESTING_XCTEST_INTEROP_MODE=complete` in its scheme and tasks so assertions in shared helpers cannot silently become warnings during mixed-framework migration. Never nest an expectation macro inside a callback expression passed to another expectation: call the operation first and assert its result and observed callback values separately.

Next migrate the seven remaining hosted suites after checking their state ownership. UIKit input tests need MainActor isolation. Preferences/session tests touching UserDefaults or process-wide settings need a common serialized scope or injected per-test stores, not independently serialized suites that still race each other. SQLite/import/outbox tests must keep temporary databases, WAL/reopen/rollback cases and account-fencing assertions. Legacy API tests should migrate only if their implementation survives the native-client cutover. XCUITest remains for launching and operating the app; a unit-test framework change does not replace real review, keyboard, voice or offline UI checks.

An actual migration failure exposed an obsolete SwiftFormat 0.52 build phase which rewrote Testing macros as invalid `#expecttry` tokens. The build phase, helper package and old formatter configuration are removed. Apple's bundled `swift format` uses the root configuration and runs explicitly, so formatting no longer runs during builds and no separate formatter dependency needs installation. Existing license headers are retained. This is a tooling reduction, not proof of whole-app LOC reduction.

Validated at this checkpoint: 107 shared functions on macOS/iOS; 24 Swift Testing functions plus 49 XCTest tests in the hosted iOS target; the native Mac build; and synthetic recovery UI inspection. No real-account/device claim follows from these checks.

## App-owned synchronization

`StudyStore.synchronize` now sequences app requests on the existing model actor. It shares matching work, queues an explicit send behind a read, validates the account binding before sending, and returns the committed snapshot/profile with the upload report. A refresh never silently authorizes an upload. Tokens remain in memory for the pass and are not persisted in SwiftData.

The operation outlives a cancelled waiting view; explicit account transitions call `cancelSynchronization` to fence new work, cancel and drain every lane, and preserve uncertain attempts. The Mac presentation layer separately fences late callbacks and permits disconnect during sync. Its request count remains busy until every same-account caller finishes. The obsolete upload-only cancellation API was removed.

Upload acknowledgement and download publication remain separate transactions. A download failure after a successful upload carries the completed upload report to the UI; it does not restore or resend acknowledged work. Eight new controlled-concurrency tests pass on both platforms, bringing the shared suite to 115 functions. Native Mac build and synthetic navigation checks pass. The iOS app still uses its legacy writer; adopting this shared owner is part of its controlled cutover, not a second writable queue.

## Mainboard Apple workflow

Mainboard now provides `apple toolchain` and `apple results`. The latter reads Apple's
`xcresulttool` test report instead of parsing build-log success strings. Both Swift
Testing and XCTest retain their reported totals, failures, skips, expected failures,
devices, warnings and ten slowest cases. Parameterized arguments are not counted a
second time. An exact `.xcresult` path identifies a particular run; a `Logs/Test`
directory selects its newest direct bundle and reports that path. An unreadable or
incomplete newest bundle never falls back to an older successful run. Keep the build
command's exit status too: a stale result directory is not proof of a new build.

`apple diagnostics` separately reads the build action's compiler errors, warnings,
analyzer warnings and source locations, retaining destination and target metadata.
It also works when compilation failed before tests started. A failed or unknown
build returns nonzero; malformed, missing or truncated evidence is an error.
Warnings remain visible on successful builds. The `build_successful` field does
not claim tests passed, and an incremental build is not a whole-project warning
inventory. Use this report to drive Swift concurrency and deprecated-API migration
instead of grepping console logs. For a fresh Mac build:

```sh
mainboard run --as-is usagi-build-mac -resultBundlePath /private/tmp/usagi-mac-check-001.xcresult
mainboard run --as-is usagi-diagnostics /private/tmp/usagi-mac-check-001.xcresult --json
```

Use root Mainboard lint for selected Swift source files, including new untracked files:

```sh
mainboard run --as-is mainboard lint --check --only swift-format apps/usagiunagi/StudyKit/Sources/StudyPersistence/StudyStore+Synchronization.swift
```

Omit `--check` to format. The old `git diff | xargs` tasks were removed. This fork is
not registered as a parent submodule, so Mainboard's no-path changed-file discovery
does not enter it: pass the changed files explicitly. A directory intentionally
checks every nonignored file beneath it. Apple's bundled formatter uses `.swift-format`;
no extra formatter package or build-phase mutation is needed.

Continue using the existing bounded build/test tasks. Hosted and UI tests currently
share derived data and a simulator, so run them sequentially. SwiftPM retains
`Package.swift`/`Package.resolved`; CocoaPods retains `Podfile.lock` until migration.
Mainboard owns the developer commands and environment, while Apple's native tools
resolve Swift dependencies. Task/lint changes do not require an unrelated environment
upgrade. The root configuration is local to this workspace, separate from this fork.

The simulator inventory is read-only; it does not establish scheme eligibility or
boot a device. The configured tasks select Xcode explicitly because the machine's
default command-line selection may not expose `simctl`. Do not fix that by changing
global `xcode-select`. Build/test tasks now refuse automatic Swift package version
changes. Restore dependencies with their dedicated tasks and review upgrades
separately; no second dependency lock or custom Swift package resolver is introduced.

For a new simulator test run, append `-resultBundlePath` with a fresh path to the
Mainboard task, retain its exit code and inspect that exact bundle. For example:

```sh
mainboard run --as-is usagi-test-ios -resultBundlePath /private/tmp/usagi-shared-check-001.xcresult
mainboard run --as-is usagi-results /private/tmp/usagi-shared-check-001.xcresult --json
```

Choose a new name for every invocation; Xcode refuses an existing bundle. This
avoids mistaking an older run for the one just launched. Poll the original process
handle rather than starting duplicate builds when an observation times out. Shared
simulator, app and UI tasks remain sequential; command-line shared macOS tests and
independent Mac builds can use their own build directories.

## Image-only radicals

WaniKani's [radical API](https://docs.api.wanikani.com/20170710/#radicals) supplies SVG
images. Apple's [SwiftUI WebView](https://developer.apple.com/documentation/webkit/webview-swift.struct)
provides the system renderer for native reviews. The surrounding feature is Swift
and SwiftUI, with a small HTML/CSS image wrapper in Swift source; SVG rendering still
uses WebKit. This is the remaining rendering dependency, rather than a claim that
SwiftUI `Image` itself decodes SVG. No review type is disabled.

The cache validates HTTPS CDN URLs, response status/URL/MIME type, bounded size and
SVG structure before atomic publication. URL versions have distinct keys. Downloads
use an ephemeral, credential-free session, refuse redirects and coalesce by URL.
Cancelled views do not cancel an already owned download. Previously downloaded
images survive reopening offline; corrupt cache files are replaced only after a
valid replacement arrives. First-time offline images still require a download.

Web content receives only a local data image, with JavaScript disabled, a
nonpersistent website store and a restrictive content policy. Inner SVG titles are
hidden from accessibility to avoid exposing the answer. Dark appearance inverts the
monochrome strokes. Answer entry and voice are disabled until loading succeeds;
errors offer retry, and native reviews always allow deferral. Cancellation does not
publish an obsolete load error into a newer task.

The Debug-only `ReviewFixture RadicalFixture` launch arguments exercise a real public
WaniKani radical with synthetic, memory-only study state and disabled account writes.
`LightFixture` or `DarkFixture` controls that preview's appearance only. Light/dark
rendering, meaning submission and retained Saved work were checked directly. Unit
tests independently cover offline reopening, cancellation, corrupt cache replacement,
invalid URLs/responses and radical-only grading/outbox behavior. Catalog-wide media
prefetch, cache-management UI, audio and replacing the old iOS SVGKit integration
remain tracked requirements.

## Native subject details

Mac browsing and review reveals now share `NativeSubjectDetailsView`. It reads full
content through `StudyStore.subjectDetails`, including unsent local notes and
synonyms, and renders mnemonics/hints, reading labels, examples and related subjects
with native SwiftUI text and navigation. Reading review reveals prioritize reading
explanations; other contexts group meaning explanations first. Related content is
filtered by account, availability and verified subscription access, with an explicit
notice when the saved graph is incomplete. The read neither edits notes nor queues
uploads.

`StudyMarkup` parses WaniKani's existing mnemonic tag vocabulary into ordered text
runs. SwiftUI maps these to attributed text, semantic subject colors, emphasis and
web links. Unknown/malformed text and leading/trailing whitespace survive; Unicode
ranges use Foundation's UTF-16 indexing consistently. Links use HTTP(S) only and do
not execute markup. The existing iOS protobuf formatter is still used by its legacy
screens; this shared implementation is the replacement for the native surfaces.

Synthetic UI checks cover catalog hit targets, rich details, related navigation,
vocabulary context sentences, persistent sheet dismissal and review reveals.
The native notes/synonyms form now saves through `saveSubjectMaterial`, which
revalidates account/content access and the captured material revision on the store
actor. No-op saves leave upload state unchanged. Existing durable queue ownership,
server identity and uncertain-attempt protection remain intact. Local synonyms
immediately participate in the normal review grader, including an already-open
session. Saving does not upload; Saved work remains the explicit sending action.

Notes retain their exact whitespace and Unicode. Synonyms use separate editable
entries rather than comma/newline parsing, preserving existing string boundaries.
This follows the [WaniKani study-material API's string and array fields](https://docs.api.wanikani.com/20170710/#update-a-study-material).
Cancelling a changed draft asks before discarding it. A stale save retains the
draft, shows the current saved version and requires an explicit replacement choice;
the replacement still checks the compared revision. Drafts are view state until
Save succeeds, not crash-recoverable autosaves. Errors stay visible while scrolling.

Direct synthetic Mac checks verified save/reopen, multiline Japanese text,
synonym addition, cancel/retain/discard, two-window conflict comparison and explicit
replacement, and the pending entry in Saved work. Shared tests independently prove
disk reopening, no-op and clear behavior, stale revisions, current content access,
uncertain-upload preservation and normal grading with a newly edited synonym.
Audio, Japanese font preferences, richer catalog filters/progress and the iOS
detail-screen cutover remain open. The existing iOS editor remains until that
cutover; compiling this shared form on iOS does not claim its caller migration.

## Native review preferences

The Mac review page reuses `ReviewSettingsPanel` and the shared `ReviewPreferences`
value. `StoredReviewPreferences` wraps AppStorage observation; edits merge only
changed fields into the current value so another window's unrelated changes survive.
The Mac window root applies appearance, including sheets. iOS keeps its archived-key
adapter until its wider settings migration. No second synchronization service or
preference dependency is needed.

The native page applies question size, stage presentation, skipping, correction
availability and partial/full reveal choices. An exact-match near miss uses the
normal grader but leaves the durable session and pending answers unchanged, allowing
a precise retry without a penalty. Explicit All information reveals the remaining
question type. Ordinary settings changes preserve the current answer draft.

Mac audio playback and the font library are still open, so their controls are not
presented there yet. iOS retains both. Practice/Anki, lessons and complete option
parity remain tracked separately. Automated checks cover merging/serialization and
exact matching; synthetic UI checks cover draft retention, reveal/correction/skip
behavior and appearance persistence. No live account or microphone validation is
claimed by this checkpoint.

## Offline katakana practice

`KatakanaPractice` owns the original deck and uses the shared grader/session engine
without an account, store or network dependency. Native Mac practice is SwiftUI and
available before account connection. It keeps temporary progress in the session
sheet; ending practice discards that local session. Completing cards cannot create
WaniKani submissions. The iOS practice host reads the same deck. Its landing menu
now shares `KatakanaPracticeMenu` with Mac through a small UIHostingController;
the old table card, custom colors, waves and constraints are removed. The existing
review host retains its keyboard and options until that migration is complete.

Typed kana/romaji, reveal, correction, deferral and accuracy share ordinary study
semantics. The Japanese voice panel captures a question token; a late answer cannot
mark another card. Native practice and ordinary reviews now bind the voice sheet
to that captured request instead of maintaining a separate presentation flag.
The Mac practice sheet supplies an explicit microphone control because its nested
navigation toolbar was not visible during verification. First presentation and
keyboard cancellation are verified; actual microphone/model tests remain open.

All 107 deck entries preserve their original order, including the repeated エ.
The new tests complete the deck with zero submissions and cover incorrect retries,
corrections, invalid input and stale question rejection. Full practice options,
Anki mode and Japanese font selection in the new native session remain tracked
work; the iOS session retains these options. Focused UI tests verify typed and
reading-only Anki practice through the shared landing menu, including draft
retention, the existing completion summary and returning to Practice.

The iOS session completion screen now uses shared `SessionSummaryView` and
`StudySessionSummary`. A small storyboard-created hosting controller retains
legacy repository lookup, radical images, subject-detail navigation and hardware
Return dismissal. The custom table completion card is removed. Mac completion
adoption and removal of the unused illustration/generated accessor remain open.
The checkpoint passes 156 shared macOS tests, the native Mac build and three iOS
UI flows; summary screenshot inspection and shared iOS/hosted-suite reruns remain
pending. Work paused at the user's request; full migration is not complete.

## Resumed cleanup scope

The user resumed work and clarified that active features must be replaced before
their legacy UI is removed. All four Go files, go.mod/go.sum and the unused C++
SQLite inspection extension are removed. The similar-kanji generator is now Swift;
its output preserves the 2,380 source characters and 44,828 candidate links in
both committed runtime supplements. Equal-score candidates now have deterministic
source ordering; the bundled files themselves are unchanged. Protobuf generation
targets Swift directly, and SwiftProtobuf/system SQLite remain necessary for the
existing cache and read-only legacy importer.

The detailed upcoming-review screen now uses shared `UpcomingReviewsView` through
a narrow hosting controller. Its existing hourly buckets, cumulative totals and
SRS/subject breakdowns remain; native disclosure rows use explicit category names
instead of color-only counts. The unused custom redesign-feedback card, preference
and completion illustration are removed; Settings retains its feedback link and
asset accessors were regenerated. Non-curriculum practice results say “Missed
items” rather than inventing a level zero.

Swift domain, persistence, networking, speech and test code is intentionally
non-UI. Active UIKit screens, the keyboard bridge, Haneke bridging header and
vendored Objective-C dependencies remain until replacement preserves their
callers. WatchConnectivity and Speech/AVFoundation are platform services;
SwiftUI does not replace them. This cleanup disables no study feature and does
not complete the migration or establish whole-app LOC reduction.

The resumed checkpoint closes the prior shared-iOS/hosted-suite and retained
summary screenshot checks: 156 shared functions pass on both platforms, 73 hosted
tests pass, all 13 iPhone UI flows pass, and two focused iPad flows pass. Screenshots
for the shared summary and schedule were inspected on iPhone/iPad. The native Mac
build succeeds. Mainboard's exact bundles are recorded in TASKS.md; legacy iOS
warnings and physical-device/account/microphone gates remain open. Mainboard tasks
`usagi-similar-kanji` and `usagi-test-ui-ipad` cover the new developer workflows.

## Native note recovery

Saved work now compares a pending note with a fresh, account-verified WaniKani
read. The user sees the current local edit, any older attempted revision, and the
server version before choosing to keep the edit queued or adopt the shown server
version locally. Both choices require confirmation. Comparison and resolution do
not submit a note or replay a review answer.

Keeping an edit persists the compared server ID and full note/synonym content,
including observed absence. The normal uploader rechecks this baseline before a
write; a changed, created, deleted or replaced record returns to recovery without
sending. A confirmed older upload advances the baseline for a newer local edit.
Stale windows, changed attempt metadata, account disconnect and cancellation are
fenced on the store actor. Recovery reads share its existing synchronization
exclusion/cancellation owner and preserve account backoff, including when a local
edit races a throttled response. No second queue or credential store was added.

The [official study-material contract](https://docs.api.wanikani.com/20170710/#study-materials)
documents subject-filtered GETs and record-specific updates. It does not document
an atomic conditional-update guarantee; read-before-write checks cannot prevent
another client changing a note during the final request. This limitation is stated
in the UI in plain language. Server equality is used as the user's chosen current
state, not as proof that a historical write succeeded. Uncertain review/lesson
reconciliation remains a separate open gate before the iOS writer handoff.

The Mac debug-only `ReviewFixture MaterialRecoveryFixture` mode supplies an
in-memory pending note and a GET-only synthetic server comparison. It bypasses
Keychain and keeps refresh, connect, disconnect and saved-work uploads disabled.
Normal and release account paths retain the real client and account checks.

## Native saved-answer recovery

Saved work now shares one account-verified comparison lane for notes and review/lesson
answers. The Mac hosts it entirely in SwiftUI. For answers, a fresh assignment read
is shown alongside the original saved payload; it never serves as an upload receipt.
The user can keep the work pending or explicitly archive it locally. A SwiftData
transaction preserves the exact answer and cached/observed progress, removes the
pending row and invalidates that subject's stale assignment. The archive has native
Transferable/ShareLink JSON export and is never uploaded automatically.

A persisted snapshot flag requires a full refresh before incomplete statistics are
shown. Failed refresh and process restart preserve the flag; old JSON defaults to a
complete snapshot when the additive key is absent. Local mistake metadata, unrelated
queues and the read-only archive survive. Stale comparisons and account/cancellation
changes are fenced on the same actor as synchronization. The ordinary uploader's
rejected-request path remains separate.

The [review creation contract](https://docs.api.wanikani.com/20170710/#create-a-review)
and WaniKani engineering's [Get All Reviews announcement](https://community.wanikani.com/t/api-changes-get-all-reviews/61617)
do not provide a reliable historical receipt for an uncertain write. No blind replay
or exactly-once guarantee is added. Native synthetic UI and persistence tests cover
these choices; the iOS writer/caller handoff and broader real-account/device checks
remain open. See TASKS.md for exact checkpoint evidence.

## SwiftUI presentation and file audit — 2026-10-18

The user's current priority is SwiftUI presentation and deletion of replaced UI,
while retaining familiar WaniKani colors and study interactions. Storage cutover
remains required; it no longer precedes every screen migration. The original
upstream default branch is `master` (`d20defc`), used as the lesson/review behavior
reference. Identical layouts are not required.

Mainboard's bounded source/resource/project searches checked the following files
individually. References in storyboards, XIBs and Xcode build groups were included;
absence of a Swift caller alone was not treated as proof that a UI class was unused.

| File | Decision and remaining responsibility |
| --- | --- |
| `ios/Features/Lessons/LessonPickerViewController.swift` | Replaced its collection/cell/header/footer implementation with a small SwiftUI host. Keeps the existing cache, available-item revalidation and navigation. |
| `ios/Features/Lessons/LessonsViewController.swift` | Replaced page-controller navigation with shared SwiftUI subject/quiz chips, swipe and keyboard handling. Keeps the quiz instance so an unfinished draft survives page changes. |
| `ios/LessonsPageControl.swift` | Deleted; its custom sizing/layout and all project references are replaced. |
| `ios/Resources/Lessons.storyboard` | Retains only the hosting scene and navigation identity. Removed page-control/back outlets and constraints; delete the scene when shell navigation migrates. |
| `ios/BottomSheetAction.swift` | Deleted the unused custom action/sheet controller after checking both type names across sources and resources. Existing review menus use SwiftUI. |
| `ios/BiggerTapAreaButton.swift` | Deleted; no remaining source or Interface Builder caller. Removed its project references. |
| `ios/SubjectChip.swift` | Deleted after replacing the last component/combination/similar-subject callers with native SwiftUI related-subject buttons. |
| `ios/Tables/SubjectCollectionModelItem.swift` | Deleted with the replaced subject-chip layout. |
| `ios/SubjectDetailsView.swift` | Replaced its 758-line table implementation with shared SwiftUI content and a value/action cache bridge under Features/Catalog. No table editor or bitmap sentence blur remains. |
| `ios/SubjectDetailsViewController.swift` | Replaced with a small SwiftUI host under Features/Catalog. Keeps existing storyboard/deep-link/navigation identities and keyboard commands; editing now saves explicitly through the existing checked writer. |
| `ios/SubjectCatalogueViewController.swift` | Retained: still has active page-controller navigation, independently of the replaced lesson navigation. |
| `ios/WavesView.swift` | Retained for login; subject-detail headers now use shared SwiftUI. |
| `ios/GradientView.swift` | Retained: Main and Vacation Mode still reference it from code and Interface Builder. |
| `ios/MainTitleView.swift` | Retained with its XIB: active home header. |

All 18 shared view/support files now live under StudyUI's `Catalog`, `Lessons`,
`Practice`, `Recovery`, `Reviews`, `Shared` and `Statistics` feature folders. They
remain one Swift package target with the same public API; no wrapper modules,
parallel navigation system or new runtime dependency was added. Lesson adapters
are grouped under `ios/Features/Lessons`, with their existing Xcode references
updated. Mainboard builds both platforms after discovery of the moved sources.

The lesson picker uses a compact four-column subject-color grid (two columns at
accessibility text sizes). Teaching/quiz navigation uses direct subject chips and
one Quiz control. Reviews again show white glyphs on the WaniKani subject color,
with a dark reading strip and a native meaning strip. Study font settings remain
owned by their existing hosts. Rich teaching and review details now render directly
in SwiftUI. The quiz retains its existing controller/input/writer adapter; replacing
presentation does not finish the persistence, shell or Mac lesson migration.

Coverage no longer stores a selected chart row as a sheet item or schedules a
second presentation on dismissal. Each explicit target button expands its current
remaining-kanji grid in the page. The bundled StudyCore curriculum and saved
WaniKani snapshot are the default data source, without a coverage download. Only an
explicit kanji action opens its separate destination. Sources and calculation
details also expand within the page, so the shared dashboard presents no sheets.
The bundled library is decoded once per app process. See TASKS.md for
exact test evidence and remaining acceptance gates.

## Shared rich details and editing — 2026-10-18

`SubjectDetailsContent` and `StudyMaterialEditor` now serve iOS teaching, review
reveal, catalog details and the native Mac store. They take immutable subject/material
values and host actions. The editor's generic revision type bridges the existing
iOS Int64 revision and the native store's UUID without erasure or a second writer.
The iOS adapter reuses the read-only importer's catalog conversion and the original
audio, artwork, font, sentence-highlighting and navigation services. Teaching renders
directly in SwiftUI; only the quiz retains its existing controller/input/writer host.

A meaning/reading visibility value keeps unanswered information concealed, including
reading explanations that could reveal meanings. Context translations now use an
explicit native reveal button rather than bitmap blur; hidden English is absent
from the accessibility tree. Existing archived preference keys are retained. The
editor provides explicit Save/Cancel, discard protection, a keyboard Done action,
and revision-conflict comparison/replacement. An unchanged note preserves exact
bytes, synonyms and exclusion-marker placement. Conflict replacement applies only
revealed editable fields to the currently compared material, preserving hidden
reading notes and its current exclusion flag. iOS identity/revision validation and
queue insertion share its existing database transaction; no-op saves do not enqueue.
Native new-session selection honors imported vocabulary exclusions, while a resumed
session keeps its recorded work unchanged.

Additional file decisions from Mainboard's exact source/function/resource/project
audit follow. The scene retains only its SwiftUI host identity; generated scene
accessors remain valid until shell navigation migrates.

| File | Decision |
| --- | --- |
| `ios/Tables/ReadingModelItem.swift` | Deleted; shared reading labels and audio actions replace it. |
| `ios/Tables/ContextSentenceModelItem.swift` | Deleted; shared context sentences retain conjugation highlighting and explicit translation reveal. |
| `ios/Extensions/CGContext+Blur.swift` | Deleted after checking all helper symbols; the removed sentence renderer was its last consumer. Removes that Accelerate import and manual bitmap contexts. |
| `ios/Tables/MarkupModelItem.swift` | Deleted after checking the global `render(formattedText:standardAttributes:)` functions; their last detail-table caller is replaced by the existing shared markup parser and SwiftUI attributed text. |
| `ios/Tables/ArtworkModelItem.swift` | Deleted the table wrapper; retained its native cached request view as Features/Catalog/SubjectArtwork.swift. Offline artwork/prefetch remains a separate open task. |
| `StudyUI/Catalog/NativeStudyMaterialEditor.swift` | Replaced by one generic StudyMaterialEditor, used by both stores; no parallel editor implementation remains. |
| `ios/Tables/HomeHeroItem.swift` | Native SwiftUI buttons replace manual UIButton stacks; the existing table adapter and callbacks remain until Home migrates. |
| `ios/Tables/EditableTextModelItem.swift` | Retained: AppSettings still uses it for the custom email field. |
| `ios/WavesView.swift` | Retained: Login still uses it. |
| `ios/VocabularyHighlighter.swift` | Retained and reused for conjugation-aware Japanese example highlighting. |
| `ios/Features/Catalog/SubjectDetailsViewController.swift` | A temporary navigation/storyboard host. The unused showHints parameter and callers were removed; the old value was never read. Developer subject logging and practice entry remain connected. |

Apple's [item-based navigation destination](https://developer.apple.com/documentation/swiftui/view/navigationdestination(item:destination:))
keeps native related-subject navigation outside lazy content. Foundation's
[attributed-string conversion](https://developer.apple.com/documentation/foundation/attributedstring/init(_:)-1fru0)
lets the existing Japanese highlighter feed SwiftUI without a label/table wrapper.
For hardware keys, [system text/focus priority](https://developer.apple.com/documentation/uikit/uikeycommand/wantspriorityoversystembehavior)
means the default UIKeyCommand priority preserves Copy before the review correction
fallback; no recursive UIView selection walker is required. Physical keyboard and
input-method acceptance still needs a device.

These hosts are migration work, not capabilities SwiftUI cannot express. Japanese
composition currently retains its narrow UIKit input bridge; remote SVG rendering
retains WebKit until a suitable native renderer replaces it. Audio/speech,
persistence, networking and watch connectivity are platform services, not screens.
No lesson, review, note, synonym or catalog feature is disabled by this checkpoint.
Exact tests, line counts and remaining UI acceptance are recorded in TASKS.md.

## Shared catalog presentation — 2026-10-18

`SubjectCatalogView` owns native list rows, sections, search, filters, level controls
and answer visibility. `SubjectCatalogQuery` performs cancellable concurrent matching
of immutable values, with exact-before-prefix-before-substring ranking and stable
level/ID ties. Pending uploads are explicit values rather than synthetic Guru stages.
The native read projection applies account/subscription/hidden-content fences within
the StudyStore actor; it does not introduce another writable repository. iOS still
reads its current cache through one observable adapter until the writer cutover.

The native search presentation keeps its toolbar visible through
[avoidHidingContent](https://developer.apple.com/documentation/swiftui/searchpresentationtoolbarbehavior/avoidhidingcontent).
This preserves the explicit Cancel control while search is active. The existing
UIKit navigation host remains for legacy deep links, Home actions and cache callbacks;
its storyboard identities are small temporary hosts rather than retained table UI.
Search uses normal navigation instead of a nested form sheet. Cancel pops the search
screen; selecting a result replaces it with details, keeping Back directed to Home.
The paging drag is disabled outside level browsing using
[GestureMask.subviews](https://developer.apple.com/documentation/swiftui/gesturemask/subviews),
which preserves the child's gestures; GestureMask.none would disable those as well.

| Audited file | Result |
| --- | --- |
| `ios/SubjectCatalogueViewController.swift` | Deleted its UIKit page container. Level menu/buttons and bounded horizontal paging use the shared SwiftUI list. Its storyboard class identity is implemented in the one temporary host file. |
| `ios/SubjectsByLevelViewController.swift` | Deleted its level table and related storyboard; no production references remain. The unrelated generated TKMSubjectsByLevel data type remains. |
| `ios/SubjectsRemainingViewController.swift` | Deleted its table/row assembly. The adapter preserves apprentice filtering, previous-level vocabulary preference and existing review/Guru timing. |
| `ios/SubjectsByCategoryViewController.swift` | Deleted the table implementation; the adapter preserves category selection and started-only assignments. |
| `ios/SubjectsExcludedViewController.swift` | Deleted the table implementation; shared presentation reloads after returning from an exclusion edit. |
| `ios/SearchResultViewController.swift` | Deleted search-controller/delegate presentation. Shared search handles clear/cancel, Japanese/meaning/kana and exact ranking; the existing host callback still closes search and opens details. |
| `ios/Tables/SubjectListItem.swift` | Deleted the UIKit row, answer-view generators, width calculations and ShowAnswersButton after proving there were no remaining callers. Shared row content is absent from accessibility when answers are hidden. |
| `ios/Tables/SubjectModelItem.swift` and `.xib` | Deleted after checking the only references were their definitions, nib and Xcode project. |
| Five catalog/search storyboards | Reduced to blank hosting scenes preserving existing caller/class/scene identities. Removed old table/page references from the project, SwiftGen inputs and generated scene accessors. |
| `ios/Tables/SRSStageCategoryItem.swift` | Retained: the Home stage summary still uses it. The remaining Home/settings table infrastructure and input/media bridges also have active callers. |

Native Mac Subjects uses its full stored catalog and native navigation to rich details.
Sample mode projects only its explicitly synthetic summary data. Complete Mac lessons,
audio/fonts, exclusion editing and broad keyboard/accessibility acceptance remain open.
Coverage and its sources are fully inline and use bundled reference data plus the saved
snapshot by default. TASKS.md records exact tests and control-helper limitations.

## Native settings and direct app tests — 2026-10-18

The iOS settings tree now uses one typed SwiftUI NavigationStack and native forms.
Appearance, Gravatar email editing, lesson order/limits, full review settings,
subject display and logout confirmation no longer assemble UIKit table models.
Lesson reordering uses List.onMove. Shared ReviewSettingsContent supplies display,
marking and audio sections to both the quick panel and full settings, with typed
ViewBuilder additions for the complete iOS options. Existing field-wise review
preference merging remains the writer; the shared quick panel still preserves drafts.

ArchivedPreference is a temporary DynamicProperty bridge to the existing Setting
and EnumSetting values. It observes their tiny archived Data values using native
[AppStorage](https://developer.apple.com/documentation/swiftui/appstorage) and writes
through the original codec/key. Local invalidation also supports volatile test
arguments. The protocol exposes only a key and mutable value. No second writable
preference repository or incompatible UserDefaults migration was introduced.

Notification changes use the async
[authorization/settings APIs](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
and [badge setter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:)).
A MainActor model serializes prompts, keeps off changes even if clearing a revoked
badge fails, and resumes the requested preference after returning from system
Settings. The UI offers an explicit system-settings action for denied permission;
it does not open that app automatically. Permission/failure/overlap tests inject
only the three platform operations. Physical prompt/delivery acceptance remains open.

| Audited file/resource | Result |
| --- | --- |
| SettingsViewController.swift and its account table classes | Replaced by Features/Settings/SettingsViewController.swift: SwiftUI navigation/form plus a narrow scene/service host. Version copy, feedback, account header and confirmed logout remain. The host gates the outer full-screen back pan when inner SwiftUI navigation is active. |
| AppSettingsViewController.swift | Replaced by AppearanceSettings.swift; removed manual switches, text-view editing, callback retention and foreground observer. |
| LessonSettingsViewController.swift and LessonOrderViewController.swift | Replaced by one native lesson settings form and reorderable List. Original raw-enum array writes, batch sizes, apprentice limit, current-level priority and vocabulary controls remain. |
| ReviewSettingsViewController.swift | Replaced by ReviewSettings.swift and shared sections. Preserved batch/order/wrong-answer choices, conditional back-to-back/Anki controls, combined-mode reset, missing-keyboard guard, font/audio navigation and archived values. |
| SubjectDetailsSettingsViewController.swift | Replaced by SubjectDisplaySettings.swift; the old blur preference now clearly describes its existing explicit translation reveal behavior. |
| Five subsidiary settings/order storyboards | Deleted their source/build/resource references and generated factories/segues after moving navigation into SwiftUI. The Settings root is a blank hosting scene for Main's active segue. |
| SettingChoiceListViewController.swift | Deleted; native typed Pickers replace its only callers. |
| EditableTextModelItem.swift and AttributedModelItem.swift | Deleted after proving AppSettings was their last consumer; a native email TextField replaces that path. |
| SettingsTableViewController.swift and TableCards | Retained: developer tools and Home still have active callers. |
| FontsViewController | Now a small navigation host for shared FontLibraryView; the old table/download controller and download cell are removed. Core Text registers fonts and URLSession owns downloads. Native Mac adoption remains open. |
| OfflineAudioViewController and DeveloperOptionsViewController | Retained behind explicit host actions. These are migration work, not limitations of SwiftUI. Main settings UI does not claim those destinations are already ported. |

The new Swift 6 AppTests target imports the built application with @testable.
Its first five Swift Testing functions cover notification permission decisions,
resume/cancel, errors, badge failure and overlap. Importing the app into the old
Tests target exposed duplicate FMResultSet.Sequence conformances because that
legacy target recompiles app sources. Keeping new tests in AppTests avoids adding
another source copy; move old suites there incrementally. Both remain under the
main shared scheme, and Mainboard's hosted task selects both. XCUITest remains the
workflow tool. No new package dependency or Python tooling was added.

The audit at this checkpoint found that the three retained legacy celebration
switches had no consumer in the new renderer. The native feedback implementation
below restores their behavior; TASKS.md retains its UI acceptance evidence.
Native Mac full settings, login/account, developer and
download screens, iOS storage handoff and device checks remain open. Exact results
and the measured scope of deletions are recorded in TASKS.md.

A sixth direct app test verifies late account notifications after the cache has
been disconnected. The host now clears its account summary safely instead of
force-unwrapping a removed client. Latest checkpoint counts supersede the dated
validation snapshots above: 191 shared functions, 82 hosted app tests, three new
iPhone settings workflows, eight iPad regression flows and two final iPhone checks.
See TASKS.md for exact bundles and per-run scope.

## Native review feedback — 2026-10-18

The shared review screen now reports the previous correct answer, completed-item
+1 and new SRS-category estimates with SF Symbols and native caption text. It
uses the original triggers: every accepted answer, whole-item completion and
completion reaching Guru, Master, Enlightened or Burned without an uncorrected
first-answer penalty. Combined Anki answers still produce one completed item;
practice can show completion but never claims SRS advancement. The final item
continues directly to completion; no animation delays a save or navigation.

Correct-answer feedback, Completed item +1 and SRS milestone estimates share the
same form in full and quick settings. The iOS adapter preserves
animateParticleExplosion, animatePlusOne and animateLevelUpPopup archives. Native
preferences decode new fields with defaults while preserving previously saved
values, and field-wise merging still preserves other windows' unrelated edits.
The old intermediate ReviewSession.MarkResult wrapper, AnswerResult enum/conversion
and duplicated animation settings section are removed. The iOS host now uses the
shared StudyAnswerDecision directly, with unchanged save/defer/exclude ordering.
One typed mapping handles both reading and field-wise writing of archived boolean
preferences. The grading/session engine itself is unchanged.

The native store returns a transient success receipt only after the existing
session/outbox transaction succeeds. Wrong answers and exact-match hints return
no success receipt, and reopening a saved session cannot replay an effect. The
native review and practice screens consume the same presentation state as iOS.

Apple's [Reduce Motion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
and [symbol-effects removal](https://developer.apple.com/documentation/swiftui/view/symboleffectsremoved(_:))
provide the accessibility policy. Static, labelled feedback remains readable
with Reduce Motion enabled. ViewThatFits switches the feedback row to a vertical
layout when its captions need more width. No particle renderer, timer, dependency
or replacement grading path was introduced. This restores missing behavior;
it is not a claim of an overall LOC reduction or full platform parity.

## Font library and preview utility audit — 2026-10-18

The font library now uses a shared SwiftUI Form with native selection switches,
SF Symbols, URLSession task progress, cancellation, inline errors/retry and a
button-anchored delete confirmation. Existing filename-based preferences and
all eight catalog entries are retained. Downloads belong to the service rather
than the pushed screen, so closing the picker preserves the task and review draft.

| Audited files | Decision and preserved behavior |
| --- | --- |
| ios/FontsViewController.swift | Replaced by ios/Features/Settings/FontsViewController.swift. The scene remains a small UIHostingController; font rows render in StudyUI/Settings/FontLibraryView.swift. |
| ios/DownloadViewController.swift | Removed after replacing its sole remaining font-library caller. The observable model owns typed actions and URLSessionDownloadTask instances. |
| ios/Tables/DownloadModelItem.swift and DownloadModelItem.xib | Removed after the app and preview utility both stopped using them. Native Toggle, Button and ProgressView replace cell/delegate/progress formatting. |
| ios/Resources/SelectFonts.storyboard | Retained only as a hosting scene with the same identifier and navigation callers; no table/cell layout remains. |
| ios/FontLoader.swift | Retained as Foundation/CoreText logic; removed UIKit, NSObject inheritance, the unused activation wrapper and screenshot lookup. Resolves canonical PostScript names once. Managed UTF-16 buffers fix the glyph allocation leak and supplementary-kanji count. |
| ios/Services.swift | Owns the font model and loader. URLSession delegates transfer temporary-file ownership before returning; task identity prevents cancelled/obsolete callbacks from installing files. |
| ios/AppDelegate.swift and AppStoreScreenshots/FontFixture.swift | Only the Debug screenshot path injects temporary storage, volatile preferences and an ephemeral mocked session. No release fixture or real account/font-cache mutation. |
| ios/FontScreenshotter/AppDelegate.swift, ViewController.swift and Base.lproj/LaunchScreen.storyboard | Removed after the new FontScreenshotterApp.swift passed its export workflow. A native SwiftUI App replaces the UIKit lifecycle/table; a standard UILaunchScreen declaration replaces the launch storyboard. |
| ios/FontScreenshotterUITests/FontScreenshotterUITests.swift | Replaced by NativeFontPreviewTests.swift. Native Core Image produces transparent glyph exports without the old mutable pixel loop. Export names retain the original asset aliases, while the complete Japanese sample wraps without a fixed-height cut-off. |
| ios/Tsurukame.xcodeproj/project.pbxproj | Removed retired source/resource references and seven unrelated preview-target source memberships. Kept active Home/developer table files; they still have callers. Preview-target CocoaPods linkage remains separate dependency-cleanup work. |
| ios/AppTests/FontLibraryTests.swift and AppStoreScreenshots/ReviewFlowTests.swift | Added five Swift Testing functions and three font workflows. They cover original files/glyphs, corrupt/status failures, saved selection, cancel/delete, retry, task survival and unchanged review drafts. Existing settings and navigation regressions remain. |

Uninstalled preview images use template rendering and the semantic primary color;
installed fonts use their actual registered face. The shared view builds for native
Mac, but a Mac font backend and entry point are still required before claiming
font-feature parity. Core Text, Foundation and URLSession are necessary native
services; none requires disabling a feature because of SwiftUI.

Same-scope production Swift across the old/new font controllers, download cell,
loader, services, AppDelegate and shared form: **756 → 635 physical lines** (121
fewer). Preview utility production Swift: **82 → 24** (58 fewer). These counts
include comments/blank lines and exclude tests, Debug fixture files, generated
sources and third-party code; they do not describe the whole repository. Build,
workflow and visual evidence is recorded in TASKS.md. UIKit keyboard/navigation,
Mac feature parity, audio/developer screens and the iOS storage handoff remain open.
