# SwiftUI migration study

Audited 2026-10-17 against this fork and the installed Xcode 27.0 / Swift 6.4 toolchain. This is a migration plan, not a claim that the app is already entirely SwiftUI. The iPhone/iPad app now targets iOS/iPadOS 27.0. The new native Mac target requires macOS 27.0. The shared StudyKit package and Mac app use Swift 6 language mode; the remaining legacy iOS app uses Swift 5 mode.

## Recommendation

Move the application UI to SwiftUI in small, working slices. Use Swift for app-owned logic. Retain a narrow UIKit input adapter until the Japanese keyboard and composition behavior have an equivalent implementation. Preserve existing data and grading semantics. Prioritize replacing legacy persistence/networking with Apple SwiftData and async URLSession before adding further custom infrastructure; retain the working database until a verified import and cutover is ready.

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

No feature was disabled for this audit. UIKit keyboard/composition and rich-details/font-library adapters remain until parity is demonstrated. System SQLite and SwiftProtobuf remain read-only legacy-format compatibility code; Speech/AVFoundation, URLSession and SwiftData remain the native non-UI services.

## What is actually in this repository

| Area | Current implementation | Proposed treatment |
| --- | --- | --- |
| Screens and navigation | Mostly Swift + UIKit; 27 tracked storyboards and 7 XIBs across the repository, including launch screens and auxiliary/watch targets | Replace application screens with SwiftUI; remove each obsolete storyboard and generated accessor only after its callers migrate. |
| Home and statistics | Custom table models and UIKit drawing; new SwiftUI statistics screen | Native `List`, `Section`, `Label`, `Button`, `TabView`, `NavigationStack`, semantic colors and system fonts. Keep study-specific Japanese font settings. |
| Charts | Statistics uses Apple Swift Charts; the unused third-party Charts 4.1 dependency was removed | Migrate the remaining legacy upcoming-review drawing with its parent Home screen. |
| Input | Shared Swift `KanaConverter`, Swift `TKMKanaInput`/`AnswerTextField`, keyboard overrides | Objective-C conversion removed after 86,210 full-string and 11,392 interactive comparisons. Keep the narrow native adapter for selection/composition and later wrap it in `UIViewRepresentable`; physical input-method checks remain open. The review screen now hosts this input through `UIViewRepresentable`. |
| Grading | Shared Swift `AnswerGrader`/`GradingSubject`/`AnswerDistance`; thin iOS protobuf adapter | Full grader moved into StudyCore; 292,880 grade categories and 18,225 distance results compared with the original. Unicode highlight offsets fixed. Session/voice integration reuses this engine. |
| Review sessions | Shared Swift `StudySession` and SwiftUI `ReviewScreen`, hosted by an iOS repository/navigation adapter | The old review layout, constraints, waves and custom success-animation implementation are removed. Native Mac reviews use the atomic session/outbox boundary. Preserve iOS rich subject details through a temporary table adapter while CATALOG migrates; iOS durable restoration/caller cutover and full mode parity remain. |
| Offline storage | FMDB / SQLite, protobuf blobs, pending review and study-material queues | Full refresh retains offline snapshots until complete responses arrive; revision-aware transaction-level merges protect pending notes and local review progress, including local changes acknowledged while a download is in flight. Additive schema 14/15 migrations preserve existing payloads. Download callbacks honor reset/logout lifetimes. Migrate to a shared SwiftData repository with typed models, actor isolation and explicit transaction boundaries. The production StudyPersistence store verifies atomic session/answer persistence, rollback, conditional acknowledgement, note merges and separate-process recovery. Mac cache callers have switched to it, with a one-time credential-bound JSON importer. The iOS database/callers have not switched yet. SwiftData does not import this legacy schema automatically: validate a one-time import and rollback path before switching callers, then remove FMDB and replaced wrappers. Do not maintain two permanent writable stores. |
| Async/networking | Shared Swift 6 upload actor; legacy PromiseKit API/downloads, URLSession, Reachability | Immediate/background writes share one process-wide lane and reload current durable payloads. An adapter currently bridges the legacy client to async/await. Replace PromiseKit chains with URLSession async APIs and structured concurrency, deleting the replaced adapter paths. Keep WaniKani-specific response validation, rate-limit handling and account ownership; rejected/ambiguous review reconciliation remains open. Network path status is advisory, not proof a request will succeed. |
| Review quick settings | Shared SwiftUI form in native iOS/Mac sheets; SwiftUI end/wrap-up confirmation | MMDrawerController, its Objective-C hook and the drawer-specific menu controllers are removed. iOS archived preference keys remain; Mac uses observed AppStorage with field-wise merging. Audio and font-library implementation still await Mac migration. |
| Images | Haneke cache and SVGKit radical rendering | SwiftUI loads avatars. Native reviews render validated, locally cached SVG bytes through Apple’s SwiftUI WebView. Full offline prefetch, audio and legacy iOS SVGKit removal remain open. |
| Text matching | Rexy for POSIX longest-match behavior | Compare matching semantics before replacing it with native Regex. Similar syntax is not proof of equivalent highlighting. |
| Other languages | Go utilities and generated protobuf Go; C++ SQLite extension; Ruby/Fastlane/build scripts | Keep build/data tools separate from the iOS migration. Generated output should be regenerated, not hand-translated. |

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
| Rich review answer details and font library | Temporary UIKit adapters; these can migrate to SwiftUI | Preserve mnemonic markup, editable notes/synonyms, audio, subject links and font downloads while CATALOG/SETTINGS migrate. Quick settings and end/wrap-up controls are now SwiftUI. This is staged work, not a SwiftUI limitation. |
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

## Validation of the iOS 27 slice

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
