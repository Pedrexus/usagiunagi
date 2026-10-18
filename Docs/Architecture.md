# One shared codebase

`Shared/Package.swift` is the common implementation for iPhone, iPad and Mac. Its package name remains StudyKit; the public modules are StudyCore, StudyPersistence, StudySpeech and StudyUI. Swift 6.4, Swift 6 language mode, Sendable domain values, actor-owned persistence and MainActor SwiftUI are already enabled there. One multiplatform target in `App/UsagiUnagi.xcodeproj` consumes that exact package. `App/UsagiUnagiApp.swift` is the common SwiftUI entry point, with native Mac and iOS/iPadOS destinations.

| Boundary | Shared responsibility | Remaining platform work |
| --- | --- | --- |
| Domain | Grading, kana conversion, sessions, lessons, preferences, curriculum and statistics | Remove legacy protobuf adapters after the iOS writer handoff |
| Data | URLSession API client, SwiftData store, durable outbox, recovery and audio downloads | iOS still uses its legacy SQLite writer; Mac uses the shared store |
| Presentation | SwiftUI review, lesson, catalog, details, settings, Home and statistics components | Common SwiftUI scene entry; temporary iOS controller presentation and persistence glue still differ from the native shared-store path |
| Speech | Apple capture and confirmed transcript flow | Physical microphone, model availability, interruptions and latency validation |
| Platform | Small capability and layout adaptations | Lifecycle, windows, notifications, badge, audio session and Keychain configuration |

The next consolidation is **one observable app model**, owning account, sync, session and media state over one repository API. Migrate iOS to the shared persistence actor with schema 9–15 import, pending-work preservation and rollback checks before retiring its current writer. The SwiftUI `App`/scene root is now shared. Next share route/state ownership, adapting compact navigation to tabs/stacks and wide windows to a split view. Do not introduce parallel iOS/Mac feature implementations or replace safe persistence with a second live writer.

Put business behavior and screens in Shared. Keep `#if os(...)` at the narrow platform capability edges; prefer layout and availability adaptation inside views. There are no separate iOS/macOS app roots. `App/Platform` contains temporary capability bridges; platform configuration stays in `App/Configuration`. The remaining watch target is a companion, not another phone/Mac app.

## Bridges still required

- iOS lifecycle, controller presentation and the small remaining storyboard shell are migration work, not a permanent SwiftUI limitation.
- The UIKit text-input adapter still protects Japanese IME composition, selection and caret behavior. Remove it only after physical keyboard/IME parity is demonstrated with native SwiftUI input.
- SVG radical rendering uses a renderer bridge until a native resource/conversion replacement preserves the same content.
- Apple system services such as Keychain, notifications, audio session setup and window commands are Swift APIs used by SwiftUI; they do not require a second UI implementation.
- Existing watch/complication support is retained. Its small companion target and resource packaging need a separate parity audit before replacement/deletion.

Shared code must preserve typed grading, Anki scopes, lesson navigation, offline queues and account isolation. Build success alone does not establish feature parity. The full prior migration analysis and evidence are retained in [history](History/migration-checkpoints.md); [current tasks](TASKS.md) are authoritative for unfinished work.
