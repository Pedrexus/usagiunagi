# Current modernization tasks

This is the current task list. Preserve functionality, commit to `codex/swiftui-27-curriculum`, and do not create PRs or push. iPhone Duo work is deferred. The repository is `/Users/pedro/Developer/Projects/apps/usagiunagi`. Detailed earlier checkpoints remain in [history](History/task-checkpoints.md); their paths and counts describe those earlier runs.

| Requirement | Current state | Remaining acceptance |
| --- | --- | --- |
| Fork, app/repository rename and localized identity | Done in source: Pedrexus/usagiunagi; 兔鰻 in ja/zh, usagiunagi elsewhere; abstract layered kanji icon | Independent signing and store distribution are not configured or published |
| Native WaniKani-inspired design | Shared SwiftUI screens use WaniKani subject colors, system fonts, SF Symbols and native Apple controls | Shared Mac Home/navigation parity, complete accessibility, adaptive layout and real/full-account review |
| One Swift/SwiftUI codebase | Shared Swift 6.4 package owns domain, persistence, speech and feature UI; one multiplatform app project consumes it | One app target and SwiftUI scene root now build for iOS/native Mac; shared app model/route ownership and iOS writer cutover remain; the legacy boundary remains Swift 5 |
| Trim and reorganize folders | App, Shared, Resources, Docs; one app project; general tooling moved to Mainboard; obsolete CI/release/snapshot tooling retired; generated Pods ignored | Continue deleting adapters only after equivalent shared behavior is verified |
| GitHub Actions as primary CI | Mainboard-native iPhone/iPad matrix, shared tests, restart checks and native Mac UI gate prepared | Publish the pinned Mainboard commit and app branch only after authorized pushes, then run hosted CI; no hosted pass claimed |
| Grading, kana and reviews | Shared deterministic grader/session and familiar typed/Anki experience integrated; prior comparison evidence retained | Physical Japanese IME/caret validation; complete app/platform parity |
| Lessons and native Mac review modes | Shared teaching/picker/quiz and durable native lessons/Anki scopes implemented | Six synthetic Mac teaching/quiz/Anki cases pass together; complete device/account and platform parity still needs acceptance |
| Storage/sync and offline work | Mac uses shared SwiftData/URLSession, account-bound durable outbox and explicit uncertain-work recovery | iOS SQLite schema 9–15 writer handoff, rollback, incremental reads and end-to-end failure/relaunch checks; no automatic replay of uncertain answers |
| Voice reviews | Apple capture, transcript confirmation, typing fallback and deterministic tests integrated into shared review UI | Real microphone/model/latency/interruption checks on devices and complete platform parity |
| Statistics and plots | Swift Charts, pace scenarios, focus, JLPT reference lists, school/Jōyō/Kyōiku and selected KanKen scopes | Chronological median-pace backtesting and its plot are implemented; full-account checks, richer forecast calibration and verified intermediate KanKen scopes remain; coverage is not calibrated exam readiness |
| Coverage popup | User said it may already be fixed and explicitly asked to ignore it | Closed report; keep inline coverage and bundled offline references |
| Settings, media and notifications | Shared controls, iOS audio/font backends and some Mac settings implemented | Shared media ownership, native Mac pronunciation/fonts, notifications/badges and watch/companion parity |
| Replace remaining non-SwiftUI code | Go and unused C++ removed; migrated tables/XIBs retired; active bridges retained | Lifecycle/controllers/storyboard, IME and SVG bridges require replacements before deletion; explain any unavoidable platform edge |
| Renew tests with Swift Testing | Shared and six hosted suites use Testing; XCUITest retained for UI behavior | Retire/migrate remaining legacy suites with their callers; preserve isolation and reproducible evidence |
| Reduce LOC and dependencies | Shared implementations replace grading, kana and feature presentation; obsolete infrastructure removed | Whole-app same-scope LOC comparison and full functional parity remain unproven |
| Mainboard development workflow | Root tasks and standalone Actions use Mainboard’s general Apple executor, bounded process trees, unique results and generic URL-test host | Mainboard commit 7acaf73 tested (105 isolated cases); no parent-workspace dependency; tool commit still unpublished |

## Earlier verified feature checkpoint

Before this folder/CI reorganization, commit `1af5e27` passed 242 shared tests on each of macOS/iOS, 91 hosted iOS tests, and five review-mode UI cases on each of iPhone/iPad. Native Mac app and six UI cases compiled; zero Mac UI cases executed because the local runner timed out enabling automation. See [the receipt](Validation/2026-10-18-native-review-modes.json). Reorganization verification is recorded separately and must not reuse those counts as new passes.

## Next consolidation

Follow [the shared-code architecture](Architecture.md): one observable account/sync/session/media owner, then the verified iOS persistence handoff and shared navigation/scenes. Small platform adapters remain for system capabilities and verified input/rendering gaps. Do not disable existing features or create two permanent writers.

## 2026-10-18 interface reference and fixture request

The existing signed-in Chrome WaniKani dashboard was inspected read-only: lesson/review cards, forecast, recent mistakes, Extra Study, level progress and Item Spread. Shared Home now follows that hierarchy with system typography, SF Symbols, tinted native buttons and subject colors. No live lesson/review/exercise was opened and no progress changed. The iPhone review rotation hang was fixed by preserving input view identity with `AnyLayout`; its isolated landscape grading test passed.

The levels 1–3 **display preview** is prepared: 357 real subject references from visible, read-only level pages, Zstandard Parquet through Mainboard, matching bundled JSON and a native Mac offline browsing option. No browser credential, account progress, WaniKani IDs or full answer rules were captured. IDs in the sample snapshot are negative; authenticated review/lesson/upload paths remain unavailable in sample mode. See [fixture provenance](../Resources/Fixtures/README.md). Complete API-grade review/lesson fixtures remain open until an authorized catalog export is available.

Current reorganization verification is in `Docs/Validation/2026-10-18-unified-app.json`. Earlier layout passes remain baseline evidence, not substitutes for the latest code. The native Mac window/lesson gate is resolved in the newer [pace and Mac acceptance receipt](Validation/2026-10-18-native-pace.json); full platform parity remains open.

## Unified-app checkpoint before the Mac launch fix

Shared suites now pass **244 tests on each of macOS and iOS**, including the bundled preview/isolation checks. Hosted iOS passes **91**. The full iPhone UI run finished **45/46**, with one unsuccessful reorder gesture; the final five-case rerun passed after using a sustained drag and waiting for the actual persisted order, also covering final Home and cold/warm routes. The final iPad layout/lesson, scene-route and polished-Home checks passed separately. These are separate runs, not a claimed 46/46 full rerun. Native Mac Release and clean standalone consolidation builds pass; separate-process persistence/catalog checks and 105 isolated Mainboard checks pass.

Native Mac read-only preview launch, Japanese search and subject details were visually verified. At that checkpoint, XCUITest created no study window. The launch problem and synthetic Mac lesson/Anki acceptance are resolved by the newer checkpoint below. Full API grading metadata, the iOS writer/app-model handoff and the physical-device/platform parity items above remain open. No hosted Actions run, push or PR was performed. The receipt records exact bundles and the standalone run's earlier source scope.

## Native Mac acceptance and chronological pace check

The unified app's complete native Mac suite passes **7/7**: two lesson cases, four review/Anki/settings cases and one inline statistics case. Option-style fixture arguments fix the no-window startup. Tests now use the actual AppKit accessibility values and switch role. The final chart-only rerun also checks the visible explanation and captures only the app window. These tests use isolated synthetic data, not live WaniKani exercises.

Shared tests pass **253 on macOS and 253 on iOS 27** (132 Core, 115 Persistence, 6 Speech); hosted iPhone tests pass **91**. The new pace check uses only earlier levels passed by each target level's unlock time, requires enough held-out history, and shows error, actual/estimated durations and observed quartile-band hits. It does not imply calibrated exam readiness. The chart uses the relevant level range and preserves distinct accessibility identifiers.

See [the exact receipt](Validation/2026-10-18-native-pace.json). This closes the synthetic Mac launch/lesson/Anki gate and implements retrospective pace validation. Full-account checks, shared app-model/iOS writer handoff, remaining platform adapters, native media/notification/watch parity, physical speech/IME checks, intermediate KanKen subsets and complete API grading fixtures remain open. No push, PR or hosted Actions run was performed; owner SDK annotations remain unstaged.

The final visual follow-up adds horizontal plot padding so the first/last points and level labels remain visible. Its Mac chart case passes, and the universal iOS simulator build passes with zero errors and 60 existing migration warnings (including Reachability, ClockKit and UIKit/media APIs). The receipt appends these exact bundles and source hash separately from the earlier full-suite evidence; that evidence is retained unchanged.
