# SwiftUI migration study

Audited 2026-10-17 against this fork and the installed Xcode 27.0 / Swift 6.4 toolchain. This is a migration plan, not a claim that the app is already entirely SwiftUI. The current app still targets iOS 15 and uses Swift 5 language mode.

## Recommendation

Move the application UI to SwiftUI in small, working slices. Use Swift for app-owned logic. Retain a narrow UIKit input adapter until the Japanese keyboard and composition behavior have an equivalent implementation. Keep the existing database and grading semantics during the UI migration.

SwiftUI is a UI framework, not a replacement for networking, persistence, speech recognition or data-generation tools. A repository containing several languages does not mean its screens use several competing UI frameworks. Rewriting generated or build-time code solely to improve GitHub's language percentages would add risk without simplifying the app people use.

Apple explicitly supports incremental integration in [Modernize your UIKit app](https://developer.apple.com/videos/play/wwdc2026/272/). Our new Statistics screen is a SwiftUI `List` hosted in the existing tab controller. Its calculations are separate from the view and have unit tests.

## What is actually in this repository

| Area | Current implementation | Proposed treatment |
| --- | --- | --- |
| Screens and navigation | Mostly Swift + UIKit; 27 tracked storyboards and 7 XIBs across the repository, including launch screens and auxiliary/watch targets | Replace application screens with SwiftUI; remove each obsolete storyboard and generated accessor only after its callers migrate. |
| Home and statistics | Custom table models and UIKit drawing; new SwiftUI statistics screen | Native `List`, `Section`, `Label`, `Button`, `TabView`, `NavigationStack`, semantic colors and system fonts. Keep study-specific Japanese font settings. |
| Charts | Custom upcoming-review drawing; Charts 4.1 remains a pinned dependency, but no production Swift import was found | Use Apple Swift Charts where a chart helps. Audit the old dependency's linkage before removing it. A chart is not necessary for every metric. |
| Input | Objective-C `TKMKanaInput`, Swift `AnswerTextField`, keyboard overrides | Port kana conversion into a pure Swift module with parity tests. Temporarily wrap the native text field in `UIViewRepresentable`. |
| Grading | Swift answer checking plus Objective-C edit distance | Preserve accepted answers, synonyms, blacklist handling, normalization and typo rules. The current distance uses UTF-16 units and transpositions; a naive Swift `Character` translation would change behavior. |
| Offline storage | FMDB / SQLite, protobuf blobs, pending review and study-material queues | Keep schema and transactions first. Hide them behind a repository interface. Evaluate a Swift SQLite layer separately; SwiftData is not an automatic migration for an existing database or durable upload queue. |
| Async/networking | PromiseKit, URLSession, Reachability | Migrate one API boundary at a time to `async`/`await`; specify cancellation, retries and actor ownership. Network path status is advisory, not proof a request will succeed. |
| Drawer | MMDrawerController + Objective-C header category | Replace with a native sheet or toolbar presentation as the review container migrates; then remove the drawer and its category. |
| Images | Haneke cache and SVGKit radical rendering | SwiftUI image loading can simplify avatars. Preserve deliberate offline downloads; HTTP caching does not guarantee offline availability. SVG radicals still need a rendering/preprocessing strategy. |
| Text matching | Rexy for POSIX longest-match behavior | Compare matching semantics before replacing it with native Regex. Similar syntax is not proof of equivalent highlighting. |
| Other languages | Go utilities and generated protobuf Go; C++ SQLite extension; Ruby/Fastlane/build scripts | Keep build/data tools separate from the iOS migration. Generated output should be regenerated, not hand-translated. |

## Current Apple tools worth adopting

Use native controls and navigation first: the system supplies Liquid Glass where appropriate. Avoid placing glass behind every content row. The current change uses glass button configurations on iOS 26+ and conventional native controls below that version. See [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

For the eventual SwiftUI shell, use typed navigation destinations, narrowly scoped observable state, explicit bindings for edits, and value snapshots for read-only rows. Keep grading and statistics independent of UI state. Use `@Observable` when the deployment floor permits it, with UI ownership on the main actor and background work returning safe value types.

[What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/) introduces Xcode 27 state initialization, toolbar and image-loading improvements. Toolbar priority is useful for review controls on smaller windows; image request/session customization may replace some avatar plumbing. New document APIs are not relevant to this app. The installed SDK documentation was also checked: new image customization APIs require iOS 27 availability checks. Compiler version, language mode, SDK version and minimum supported OS are distinct choices.

Do not switch the entire project to Swift 6 mode in the UI change. The baseline already has protobuf/Sendable warnings and shared mutable services. Follow the [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/): diagnose and isolate one target at a time, update/regenerate dependencies deliberately, and avoid masking errors with unchecked Sendable declarations.

### The strict SwiftUI limitation

`AnswerTextField` overrides `textInputMode` to choose an installed Japanese keyboard. Apple's [textInputMode documentation](https://developer.apple.com/documentation/uikit/uiresponder/textinputmode) describes this UIKit capability. The reviewed [SwiftUI text-input APIs](https://developer.apple.com/documentation/swiftui/text-input-and-output) do not establish equivalent language selection. A SwiftUI `TextField` replacement must therefore demonstrate parity before removing the adapter. Test marked text, selection, deletion, paste, hardware keyboards and switching between meaning and reading questions.

### Deployment floor

- **iOS 15:** preserves today's compatibility, but requires fallbacks for modern navigation, observation, charts and glass.
- **iOS 26+: recommended for this personal modernization fork.** Supports the modern navigation/observation/chart stack and Liquid Glass without maintaining the older design path; gate iOS 27-only enhancements.
- **iOS 27 only:** simplest access to the installed SDK's newest features, but excludes more devices than the core feature set requires.

The deployment floor has not been changed. A newer build SDK alone does not drop older OS support.

## Migration order and completion gates

1. **Stats and shared appearance (this change):** SwiftUI statistics, standard typography and symbols, native Home actions, preserved red error feedback. Build and test; inspect sample data in light/dark mode and enlarged text.
2. **Home, settings and navigation:** replace table-model screens with SwiftUI, introduce typed routes, preserve login/logout, search, vacation mode, settings persistence and deep links. Delete migrated controllers/layout files rather than keeping two permanent versions.
3. **Subject browser and details:** preserve mnemonic markup, links, synonyms, radical images, downloaded audio and font choices. Profile scrolling using a full-size account dataset.
4. **Review and lesson sessions:** extract a deterministic session state machine before replacing the 1,747-line review controller. Cover wrong/alternate answers, undo/ignore, Anki mode, interruption/resume, question order, queues and input behavior. Keep the small input adapter as necessary.
5. **Data and dependency cleanup:** test offline review completion, restart before upload, failed/duplicate upload responses, retry ordering, reset/vacation transitions and old-database upgrades. Only then replace FMDB/PromiseKit and remove unused dependencies. Migrate the watch companion independently.

Use XCTest for existing coverage and UI workflows; new isolated Swift modules can use Swift Testing. Use previews for empty, loading, offline, vacation, error and populated states, then verify actual Simulator/device behavior. Preview success is not proof of sync correctness.

Track app-owned production LOC, storyboard/XIB size, dependencies and behavior coverage separately. The Home action component shrank from 406 to 114 physical lines; the statistics feature adds code, so this change does not claim a net reduction across the whole app. Splitting a large file into smaller files alone is not a reduction.

## Voice reviews after the session boundary exists

Prototype tap-to-speak as another answer input into the same grading path. Evaluate [SpeechAnalyzer / SpeechTranscriber](https://developer.apple.com/videos/play/wwdc2025/277/) with runtime checks for supported Japanese/English locales, device support and downloaded model availability. Retain typing and cancellation. Never grade interim transcripts or callbacks belonging to an earlier question. A recognized kanji transcription is not evidence that the learner pronounced the expected reading; test this explicitly on a physical device. Transcription is not pronunciation scoring.

Voice recognition is not implemented in this change.
