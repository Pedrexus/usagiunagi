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

`StudyRootView` in that same module owns the native Home/Practice/Stats shell and one navigation stack. Study screens open above the tabs; Back pauses the session and Home offers Resume. Home reads use SwiftUI task cancellation and a minute timeline. `StudyAvailability` is the common native Home/session selector; practice uses `StudySession` without assignment/statistics/review-upload effects. `ReviewScreen` is presentation content: native, legacy iOS and sheet hosts each supply one navigation stack. `App/Application/StudyAppAssembly.swift` composes one app-owned service value held in SwiftUI State. It supplies the same model, media owners and preferences to every route. Synthetic accounts and server responses live in `App/AppStoreScreenshots/NativeStudyFixture.swift`, behind DEBUG; a single factory chooses that environment. The native and temporary iOS hosts share the font fixture definition. No native feature screen belongs in assembly.

Mac consumes the shared root/model/store. iOS still uses its legacy coordinator/writer with the common Home, tab and review components. Sharing the app entry point does not complete that ownership handoff. Finish sign-in, route, preferences/media and platform parity before selecting the native iOS writer; then verify schema 9–15 import, pending-work preservation and separate-process rollback/crash ordering. Do not introduce permanent parallel feature implementations or two live writers.

Put business behavior and screens in Shared. Keep `#if os(...)` at the narrow platform capability edges; prefer layout and availability adaptation inside views. There is one SwiftUI app entry point; the iOS legacy coordinator remains a temporary destination. `App/Platform` contains temporary capability bridges; platform configuration stays in `App/Configuration`. The remaining watch target is a companion, not another phone/Mac app.

## Shared lesson choices

`StudyLessonPreferences` owns the original defaults, normalized batch sizes, subject order, current-level priority, Apprentice limit and kana-only vocabulary choice. One strict level/type/ID comparator is used by native selection and the temporary iOS adapter. `StudyLessonSettings` merges individual edits into the latest stored value; all native windows share the app-owned observable instance. `LessonSettingsView` is common SwiftUI, with native list reordering on iOS and small move buttons on Mac.

Native Home, the forecast and new lesson/review/practice selection use the same preferences. The Apprentice count includes pending and excluded workload; reaching the limit disables new lessons with an explanation while preserving the available-item count. Resuming a durable quiz returns its saved queue/options before applying new selection rules. A changed preference cannot rewrite a paused quiz or bypass assignment/account validation.

Native settings use one Codable UserDefaults value. The temporary `App/Features/Settings/LegacyPreferences.swift` adapts the original iOS archived keys for lessons, reviews, subject display, fonts and audio; it replaces the former review-only adapter location. Vocabulary exclusion uses a shared control and archive-compatible lesson setting. Subject display also uses a common owner/form; other unmigrated settings and platform services still require parity work. The old app-specific lesson form is removed; no account database or iOS writer cutover occurs in this migration.

## Shared subject display

`StudySubjectSettings` is one app-owned observable preference value. `SubjectSettingsView` supplies the same nine original choices on both hosts; the skip-kanji-reading binding stays in the review policy instead of duplicating it in display preferences. Native windows merge only changed fields into their latest saved preferences. The temporary iOS adapter preserves all eight original display archives, including the inverse show-all-readings choice. Defaults match the original app: primary kanji readings and concealed context translations. Display choices do not change the grader's accepted answers.

Shared details render optional assignment dates/SRS, readings, translations and mnemonic artwork. Native similar-kanji reads resolve supplementary glyphs to accessible kanji records before applying the current-level display choice; hidden/subscription-locked content cannot leak through raw supplementary text. Only the returned projection clears that text. Native Home and catalog honor the prior-level graph choice without changing stored work or paused queues.

`StudyArtwork` decodes the original 469 artwork paths from a bundled binary Apple plist. The old app-specific artwork manager, image view, display form and duplicate stats presentation are retired. Artwork remains optional, attributed, network/cache-backed and hidden until the meaning is revealed; a missing catalog produces an inline unavailable label. See [resource provenance](../Shared/Sources/StudyCore/Resources/SOURCES.md).

Review selection now honors skipping kanji readings before choosing a new question, including random, grouped, combined and practice modes. Previously completion honored the flag while selection could still ask a reading first. Vocabulary readings and already-presented durable questions remain intact; skipped readings do not fabricate attempts or errors. Existing grading, assignment and outbox rules remain.

## Subject edits and vocabulary exclusion

`SubjectExclusionControl` is shared by native details and the temporary iOS writer host. Its visibility is the sixth lesson preference, preserving `Settings.allowExcludeItems` on iOS and defaulting to the original enabled choice for older native archives. Hiding the control does not remove an existing exclusion. The lesson form no longer needs a platform-injected vocabulary section.

`StudyMaterial.isExcluded` changes only the marker and preserves exact note text, reading notes and synonyms. Repeating the same choice preserves the original bytes. `StudyStore.setSubjectExcluded` reads the latest accessible vocabulary material on the actor and uses the existing revision-checked material writer; server identity, pending/recovery metadata and upload ownership remain unchanged. Unchanged choices are no-ops. A concurrently open notes editor receives the existing stale-version conflict instead of replacing a newer exclusion. No network request is made by the native control; Saved work owns explicit upload. The temporary iOS host retains its existing online-sync behavior.

Catalog exclusion changes future lesson/scheduled-review selection and Home counts without rewriting a paused quiz. Details inside a review do not expose that catalog control. The explicit review-menu action instead removes the current vocabulary item from the active queue after an answer is revealed, matching the original typed-review/Anki rules. Typed lessons cannot use it. The shared store commits the latest notes marker and session revision in one transaction, retaining notes, server identity, recovery metadata and earlier completed/attempted submissions. A stale or inaccessible action rolls back both writes. The excluded item receives no completion credit, assignment change or review submission; a saved material edit remains eligible for explicit upload from Saved work. A zero-completion session says “Session complete.” Hiding the lesson preference hides the action without clearing saved exclusions. The temporary iOS writer retains its original review-menu action until the cold-start writer handoff. Physical input, remaining display preferences, routes and the iOS writer handoff remain separate work.

## Shared font ownership

`StudyCore.StudyFontCatalog` owns the eight original font definitions, file activation and Japanese glyph checks. `StudyFontLibrary` owns the URLSession downloads, native Progress, cancellation/retry state and selected filenames. One library is injected by the app and survives picker navigation; both platforms use `StudyUI.FontLibraryView`. Font preview assets belong to that UI package once. The FontScreenshotter utility consumes the same catalog.

Font files are validated before cache replacement, then activated at their final file URL through Core Text. Transfer identities prevent a cancelled completion from replacing a newer download. The iOS adapter retains `Settings.selectedFonts` in its existing archived format and the original Documents/fonts location. Native Mac uses a UserDefaults string array and Application Support/TsurukameNative/fonts. The small iOS hosting controller contains no download/catalog business logic; its obsolete font storyboard and loader were removed. Native review selection and gestures use the same glyph-filtered names without clearing an answer draft.

Shared pronunciation ownership is described below. Notification/watch integration, physical media acceptance and the remaining iOS writer/coordinator still need parity work; font migration does not change account/grading storage.

## Shared pronunciation and offline audio

`StudyAudioLibrary` owns selected voices, download policy, the current account's accessible audio catalog and one playback engine. Both hosts use `AudioLibraryView`/`OfflineAudioView`; subject details and reviews consume the same player. iOS retains its three archived preferences and Documents/audio/a{subject}-{voice}.mp3 cache contract. Native Mac uses primitive UserDefaults values and Application Support/TsurukameNative/audio. Disabling downloads retains files; explicit deletion stops playback/downloads, disables downloading and retains voice choices. Priority remains current level, earlier levels in reverse order, then the next accessible level, with at most four active transfers per level.

Native catalog reads omit hidden and subscription-locked subjects and reject another account. Changing/disconnecting the account cancels active transfers and playback without deleting the cache. Repeated reads of an unchanged catalog do not restart downloads. Playback rotates voices, prefers the chosen cached recording, then any other cached voice, and only then streams an HTTPS URL. Decode failures and loading can be recovered/cancelled through shared inline controls. The cache downloader validates response status, media type and nonempty bytes; the playback engine validates actual media decoding.

`AppleStudyAudioPlayback` uses [AVFoundation's native Observation support](https://developer.apple.com/documentation/avfoundation/observing-playback-state-in-swiftui). It enables the global Observation setting before creating playback objects and creates each player lazily on play. Async observations and an item-specific completion stream replace manual KVO and UIKit alerts. Completion/failure/cancellation are fenced to that player; an old notification cannot stop a replacement. iOS releases the audio session before voice capture starts. Voice sheets hold a shared playback lease across windows and release it after capture cleanup, or after a finished transcript is confirmed for grading.

Native autoplay follows a newly persisted successful reading, kana-only vocabulary meaning, or correct combined Anki assessment. Revealing/incorrectly assessing a card or reopening a saved session does not autoplay. Stop/error controls survive the final question. Subject details use the native J shortcut. The old `App/Audio.swift`, audio delegate and offline-audio storyboard were removed. Remaining iOS files adapt its existing catalog/archive and navigation only.

The iOS background-audio policy uses AVAudioSession; macOS mixes with other apps and does not expose that mobile-only setting. This is a platform service difference, not a second UI or a SwiftUI limitation. Physical route changes, microphone/speech-model availability, interruptions and voice latency still require device acceptance. The iOS writer/coordinator and notification/watch services remain separate migration work.

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

## Scaffolding and data boundaries

Home keeps the original iPad sequence: lessons/reviews, upcoming reviews, extra study, current-level progress and all-level SRS counts. One shared SwiftUI view supplies both platforms. Compact glass study buttons replace repeated titles/buttons and decorative cards; the empty forecast stays a tappable summary instead of an empty plot. Mac uses an inset list bounded to 960 points; iPhone/iPad retain native grouped lists. Colors and SF Symbols keep the established WaniKani identity.

JSON remains the WaniKani wire format and the bundled curriculum/preview format. Codable decodes real responses; static synthetic response literals are test fixtures, not a production data source. Deleting those fixtures would remove response/recovery acceptance. SQLite remains necessary for the active iOS writer (`LocalCachingClient`, `SyncStore`, `PendingUploadStore`) and the read-only schema 9–15 importer. Removing their SQL now would lose offline, pending-work or migration functionality. Retire them after the documented single-writer handoff; the native store already uses SwiftData without app-written SQL.

The attached 01:16 navigation crash matches an earlier failed Home test by process/time. It does not reproduce in the current isolated workflows. A proposed sample launch/reopen XCUITest found only the menu bar, while a normal OS launch of the release app produced the main window. Single-window, restoration opt-out and deferred-media experiments did not resolve that harness discrepancy and were discarded. Normal WindowGroup behavior and window restoration are retained. That discrepancy is not a proven product fix or a passing UI acceptance check.
