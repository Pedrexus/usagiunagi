# One shared codebase

`Shared/Package.swift` is the common implementation for iPhone, iPad and Mac. Its package name remains StudyKit; the public modules are StudyCore, StudyPersistence, StudySpeech and StudyUI. Swift 6.4, Swift 6 language mode, Sendable domain values, actor-owned persistence and MainActor SwiftUI are already enabled there. One multiplatform target in `App/UsagiUnagi.xcodeproj` consumes that exact package. `App/UsagiUnagiApp.swift` is the common SwiftUI entry point, with native Mac and iOS/iPadOS destinations.

| Boundary | Shared responsibility | Remaining platform work |
| --- | --- | --- |
| Domain | Grading, kana conversion, sessions, lessons, preferences, curriculum and statistics | Remove legacy protobuf adapters after the iOS writer handoff |
| Data | URLSession API client, SwiftData store, durable outbox, recovery and audio downloads | iOS still uses its legacy SQLite writer; Mac uses the shared store |
| Presentation | SwiftUI review, lesson, catalog, details, settings, Home and statistics components | Common SwiftUI scene entry; temporary iOS controller presentation and persistence glue still differ from the native shared-store path |
| Speech | Apple capture and confirmed transcript flow | Physical microphone, model availability, interruptions and latency validation |
| Platform | Small capability and layout adaptations | Lifecycle, windows, notifications, badge, audio session and Keychain configuration |

`StudyAppModel` in `Shared/Sources/StudyUI/Application` owns observable account, restore, refresh and explicit-send state in Swift 6. Its typed `StudyCredentialStore` preserves the existing Mac Keychain namespace and cache path; fourteen account-model tests cover transitions, failed credential operations, pending-work preservation and cancellation.

`StudyRootView` in that same module owns the native Home/Practice/Stats shell and one navigation stack. Study screens open above the tabs; Back pauses the session and Home offers Resume. Home reads use SwiftUI task cancellation and a minute timeline. `StudyAvailability` is the common native Home/session selector; practice uses `StudySession` without assignment/statistics/outbox effects. `ReviewScreen` is presentation content: native, legacy iOS and sheet hosts each supply one navigation stack. `App/Application/StudyAppAssembly.swift` retains composition and synthetic fixtures, with no native feature screens.

Mac consumes the shared root/model/store. iOS still uses its legacy coordinator/writer with the common Home, tab and review components. Sharing the app entry point does not complete that ownership handoff. Finish sign-in, route, preferences/media and platform parity before selecting the native iOS writer; then verify schema 9–15 import, pending-work preservation and separate-process rollback/crash ordering. Do not introduce permanent parallel feature implementations or two live writers.

Put business behavior and screens in Shared. Keep `#if os(...)` at the narrow platform capability edges; prefer layout and availability adaptation inside views. There is one SwiftUI app entry point; the iOS legacy coordinator remains a temporary destination. `App/Platform` contains temporary capability bridges; platform configuration stays in `App/Configuration`. The remaining watch target is a companion, not another phone/Mac app.

## Shared font ownership

`StudyCore.StudyFontCatalog` owns the eight original font definitions, file activation and Japanese glyph checks. `StudyFontLibrary` owns the URLSession downloads, native Progress, cancellation/retry state and selected filenames. One library is injected by the app and survives picker navigation; both platforms use `StudyUI.FontLibraryView`. Font preview assets belong to that UI package once. The FontScreenshotter utility consumes the same catalog.

Font files are validated before cache replacement, then activated at their final file URL through Core Text. Transfer identities prevent a cancelled completion from replacing a newer download. The iOS adapter retains `Settings.selectedFonts` in its existing archived format and the original Documents/fonts location. Native Mac uses a UserDefaults string array and Application Support/TsurukameNative/fonts. The small iOS hosting controller contains no download/catalog business logic; its obsolete font storyboard and loader were removed. Native review selection and gestures use the same glyph-filtered names without clearing an answer draft.

Pronunciation playback, notification/watch integration and the remaining iOS writer/coordinator still need their own parity work. Shared font ownership does not establish complete media parity or change account/grading storage.

## Bridges still required

- iOS lifecycle, controller presentation and the small remaining storyboard shell are migration work, not a permanent SwiftUI limitation.
- The UIKit text-input adapter still protects Japanese IME composition, selection and caret behavior. Remove it only after physical keyboard/IME parity is demonstrated with native SwiftUI input.
- SVG radical rendering uses a renderer bridge until a native resource/conversion replacement preserves the same content.
- Apple system services such as Keychain, notifications, audio session setup and window commands are Swift APIs used by SwiftUI; they do not require a second UI implementation.
- Existing watch/complication support is retained. Its small companion target and resource packaging need a separate parity audit before replacement/deletion.

Shared code must preserve typed grading, Anki scopes, lesson navigation, offline queues and account isolation. Build success alone does not establish feature parity. The full prior migration analysis and evidence are retained in [history](History/migration-checkpoints.md); [current tasks](TASKS.md) are authoritative for unfinished work.

## Cold-start handoff boundary

Current iOS startup creates `TKMServices` in `AppDelegate`, but does not open `LocalCachingClient` there. `LegacyStudyWindow.task` later creates `LegacyStudyCoordinator`, which creates the client. Background fetch returns `.noData` while that client is absent. This source evidence provides a simpler migration boundary before the old writer starts; a working cold migration has not yet been implemented or verified.

First complete common sign-in, Home/navigation, input, media/settings and notification/watch parity. Then gate bootstrap before creating the legacy coordinator, verify the account, read one consistent schema 9–15 export and preserve pending/uncertain payloads in the native import. Credentials, import receipt and writer selection need recoverable ordering and separate-process crash/rollback checks. Keep the original data recoverable and prevent the old writer from reopening after native work changes. On identity mismatch, preserve the work and do not start an unverified writer. Do not use `clearAllDataAndClose()` for migration: that method clears the old data before closing it.
