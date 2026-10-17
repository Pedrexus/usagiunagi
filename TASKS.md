# usagiunagi task tracker

This is the persistent source of truth for the modernization. Update it in every implementation checkpoint, including evidence and remaining limitations. The active Codex goal is to carry the requested work through completion, not merely produce a plan. Work is reviewed in [PR #1](https://github.com/Pedrexus/usagiunagi/pull/1).

Status: **done** = implemented and verified for the stated scope; **in progress** = being changed; **open** = still required; **needs external validation** = implementation cannot establish the remaining behavior without a device/account. A build alone does not close a behavior task. Keep a task open if any required acceptance item remains.

## Scope and decisions

- iOS/iPadOS 27+, native macOS 27+, app-owned code moving to Swift and SwiftUI. Preserve existing study behavior unless a change is explicitly agreed.
- Basic native Apple controls, system fonts and SF Symbols; WaniKani subject identities and clear information hierarchy. No return to the rejected animal mascot; the current icon is an abstract layered 兔鰻 mark.
- 兔鰻 for Japanese/Chinese name localizations; usagiunagi elsewhere. Repository renamed to Pedrexus/usagiunagi. Store metadata is prepared, not published.
- iPhone Duo-specific work is **deferred by the user**, not a completion requirement now. Generic adaptive phone/iPad/Mac layouts remain required.
- Keep narrow keyboard/SVG bridges until equivalent behavior is verified. Inform the user before any feature must be disabled. Do not silently remove functionality to achieve a language/framework percentage.
- Keep credentials, installed-app data and durable review queues intact. App-owned Swift does not mean rewriting operating-system libraries or all build tools.

## Open work and acceptance criteria

| ID | Status | Work | Completion evidence / dependencies |
| --- | --- | --- | --- |
| TRACK | Done; ongoing upkeep | Maintain this tracker, migration matrix and checkpoint evidence | Reconcile every implementation change and user correction; do not discard unfinished tasks across turns. |
| BRAND | Done for source/local builds | Repository/name/README/icon rebrand | b65a1ea; layered kanji icon compiled for iOS/Mac/watch, installed iPhone icon inspected, four name localizations checked in iOS/Mac bundles; six login tests preserve old/new token names. Internal identifiers remain compatibility names. |
| CORE | In progress | Shared Swift 6 domain models and app-owned logic | StudyCore/StudyUI and Mac use Swift 6; remaining iOS target still Swift 5. Resolve ownership and concurrency warnings before switching it. |
| GRADE | Done for shared engine; integration continues in SESSION/VOICE | Preserve grading semantics in shared Swift | Full grader/normalization use Codable, Sendable domain values; iOS routes through a small protobuf adapter. 292,880 grade-category comparisons matched the original; 18,225 distance comparisons matched. Unicode feedback ranges corrected and component recursion guarded. Shared and iOS grading tests pass. |
| KANA | Implemented; physical input validation open | Port kana conversion/delegate from Objective-C | Shared Swift converter and 52-line UIKit adapter replace the Objective-C implementation. 86,210 whole-string and 11,392 interactive legacy comparisons matched. Tests cover all 290 mappings, case, selection, deletion, paste, delegate forwarding and composition bypass. Physical Japanese/hardware keyboard checks remain under DEVICE. |
| SHELL | Open | SwiftUI Home and app navigation | Reviews/lessons counts, schedule, refresh, search, practice, deep links, scene lifecycle and native bars; delete replaced controllers/layouts. |
| SETTINGS | Open | SwiftUI login/account/settings | Preserve preferences, vacation, logout, tokens, fonts, review/lesson options, downloads, notifications and destructive-action behavior. |
| CATALOG | Open | Shared full subject catalog and details | Search, categories/levels, mnemonic markup and links, synonyms/notes, examples, radical images, audio and Japanese font settings. Mac currently has only basic search/details. |
| SESSION | In progress | Shared deterministic review session state | Shared Codable/Sendable queue, progress, question tokens, overrides, delays and submissions now drive the iOS review screen. 960 legacy scenarios match; unit tests cover restoration and practice isolation. Remaining: durable account-bound resume coupled to outbox, SwiftUI host, Mac integration and end-to-end mode coverage. |
| LESSONS | Open | SwiftUI lesson selection/teaching/quiz | Preserve lesson order, batches, filters, audio, completion and interruption behavior; share engine with Mac where appropriate. |
| VOICE | Open | Optional English/Japanese spoken review input | SpeechAnalyzer capability/model/permission checks; explicit listening/stop/cancel, final transcript preview/correction, question-scoped callbacks, typing fallback; same grading path. Never infer a pronunciation score from transcription. Depends on GRADE/SESSION. |
| OUTBOX | In progress | Swift persistence and durable review/material outbox | Fixed stale acknowledgements deleting newer pending payloads; SQLite/restart tests pass. Still required: migration, transactional failure recovery, globally ordered uploads, duplicate/ambiguous responses, reset/vacation handling. Do not replace iOS queue with Mac's read-only JSON snapshot. |
| SYNC | Open | Async Swift API/repository boundary | Cancellation, rate limits, incremental pages, hidden/deleted data, account switching, synchronization conflicts and offline errors; WaniKani remains cross-device progress authority. Mac read-only reader is implemented/tested. |
| MEDIA | Open | Native offline images/audio and SVG strategy | Cache/download lifetime, corrupt/missing files, interruption, radical-only images and audio playback. Evaluate pre-rendered radical assets before removing SVGKit/Haneke. |
| MAC | Open | Native Mac feature parity | Statistics/basic catalog done; reviews, lessons, input, full details, media/downloads, settings, notifications, keyboard shortcuts and account workflows remain. Depends on shared engines/data. |
| ADAPT | Open | iPhone/iPad/Mac adaptive layouts | Rotation, iPad resizing/multitasking, minimum Mac window sizes, large text, keyboard navigation and focus. Initial chart layouts inspected; broad coverage remains. Duo is excluded for now. |
| STATS | In progress | Useful, credible plots and study targets | Current charts/coverage/focus implemented; validate real/full accounts, empty/offline/pending/reset states and accessibility. Intermediate KanKen scopes require verified data. No exam pass probability without non-kanji evidence. |
| FORECAST | Open | Validate performance/workload forecasts | Collect only appropriate available evidence; model explicit study scenarios; chronologically backtest against median baseline, report error/sample size/coverage. Until calibrated, keep current ranges labelled scenarios. Do not invent unavailable answer history. |
| DEPEND | Open | Remove obsolete dependencies/generated UI infrastructure | Remove only after callers migrate: FMDB, PromiseKit, drawer, Haneke, SVGKit, Rexy as semantics permit. Old Charts removed. Audit protobuf regeneration and toolchain compatibility independently. |
| WATCH | Open | Preserve and modernize watch companion | Current companion still builds and has new branding; test complication/background sync and replace deprecated ClockKit paths if retained. |
| SIZE | Open | Reduce app-owned LOC and complexity | Compare same-scope production LOC, layouts and dependencies against baseline; count added features separately. Delete replaced code instead of parallel permanent implementations. |
| QA | Open | End-to-end and accessibility validation | Review/lesson flows, VoiceOver/Dynamic Type/contrast, offline restart/upload, account switching, dark/clear icons, localization, privacy/microphone descriptions and release builds. |
| DEVICE | Needs external validation | Real-account and physical-device behavior | Safe authenticated sync, Japanese keyboards, microphone recognition/latency/permissions and audio interruptions. No real account or device validation has been claimed. Ask only when a concrete check needs user participation. |
| DISTRIBUTE | Open; publication not requested | Independent distribution readiness | Resolve own signing identifiers/entitlements, privacy text, versioning and complete store metadata before a release. Do not publish or claim App Store availability during development. |

## Verified checkpoints

- `42f2552`: reproducible baseline; 24 app tests; formatter excludes build output.
- `7c136b0`: native Home controls and initial SwiftUI statistics; 34 app tests. Home action component 406 → 114 physical lines.
- `0898bfb`: iOS/iPadOS 27 floor; shared Swift 6 statistics/curriculum modules; native Mac companion; 10 new shared tests. Current school/Jōyō reference totals 1,026/2,136.
- `b65a1ea`: rebrand, abstract layered kanji icon, localized names; iOS/Mac builds, 34 app + 10 shared + 6 mocked login tests passed. Mac sample charts/coverage/subject navigation/search and iPhone/iPad coverage layouts inspected. No real-account writes tested.

## Current execution order

1. GRADE and KANA shared implementations are in place; continue physical input validation when a device is available.
2. Extract SESSION and the OUTBOX/SYNC interfaces; migrate review/lesson UI and add VOICE using the same submission path.
3. Replace shell/settings/catalog/media and bring Mac to parity; remove obsolete implementations as each slice lands.
4. Complete forecasts, adaptive/accessibility checks, watch preservation and deployment readiness. Independent tasks may be reordered when that reduces dependencies, but remain listed until verified.

Details and source evidence: [migration study](SWIFTUI_MIGRATION.md), [statistics](STATISTICS.md), [historical baseline](MODERNIZATION.md), [branding](Branding/README.md).

### Grading checkpoint (2026-10-17)

- Removed the Objective-C NSString distance category and header; added a shared Swift implementation with three rolling rows instead of a full matrix. Directly compared against the compiled old implementation on all 18,225 pairs from exhaustive a/b/c strings through length four plus Unicode/transposition cases. All matched.
- Added an injected subject lookup to AnswerChecker so grading tests do not construct a live database/network service. Existing callers retain their original API. Nine direct grading tests cover primary/alternate readings, one-kanji vocabulary, long vowels, invalid scripts, okurigana, synonyms, blacklist precedence and typo rules.
- Validation: 43 iOS tests and 12 shared Swift Testing functions passed (including 14 parameterized distance cases and a long-input check). Full grader migration remains open.

### Kana checkpoint (2026-10-17)

- Removed the Objective-C kana implementation/headers and migrated its tests to Swift. All 290 mappings remain, grouped by kana in the shared module. Production converter/adapter shrank from 583 to 405 physical lines (including headers/comments).
- Compared the compiled original whole-string converter on 86,210 cases and its interactive algorithm on 11,392 edits using a Foundation text-field stand-in. Text, system-insertion decisions and cursor offsets matched before the two targeted fixes below. These comparisons establish algorithm parity, not physical keyboard behavior.
- Fixed the cursor endpoint when pasting a complete multi-letter romaji sequence; added a composition guard so the native input method owns marked text. Both have direct regression tests, alongside real UIKit selection/cursor tests. The original whole-string `nn` behavior is preserved independently of interactive typing.
- Validation: 43 iOS tests and 17 shared Swift Testing functions passed (21 kana and 14 distance parameterized cases). Physical Japanese keyboards, hardware keyboards and live input-method composition still need device validation.

### Shared grader checkpoint (2026-10-17)

- Extracted the complete grader/normalizer into StudyCore with Codable, Sendable question and subject values. iOS now uses the shared grader through a 60-line compatibility adapter, with no database or UIKit dependency in the grading engine. Session and voice integration can reuse it directly.
- Before refinements, 292,880 generated grades matched the original including feedback ranges. After fixing native UTF-16 feedback offsets and guarding malformed component recursion, the same 292,880 grade categories still matched; 48,483 generated Unicode feedback ranges changed as intended. Added focused tests for those cases.
- Validation: 43 iOS tests, 25 shared test functions (including meaning/reading/kana/distance parameterized cases) passed; native macOS build passed. Actual session/upload/device coverage is still tracked separately.

### Pending-upload acknowledgement checkpoint (2026-10-17)

- Delayed responses previously deleted pending reviews/materials by subject ID alone. Conditional acknowledgements now delete only when the stored payload matches the version that was sent, preserving a newer edit made while the request was in flight. No schema or stored-data migration is needed for this fix.
- Three SQLite regression tests cover matching/repeated acknowledgements, unrelated subjects, a newer progress payload surviving database close/reopen plus an old acknowledgement, and newer synonyms/notes surviving an old acknowledgement. 46 iOS tests pass.
- OUTBOX remains open: independent immediate-upload and sync chains can overlap; uploads need a shared ordering boundary and fresh queued revisions. Existing HTTP 422 handling drops progress broadly and needs reconciliation against the server assignment. Account changes, uncertain network outcomes, migration failure and rollback still need dedicated tests. This fix does not claim to resolve those separate risks.

### Shared session checkpoint (2026-10-17)

- Moved queue selection, question ordering, mistakes, overrides, retry delays, wrap-up, practice isolation and completion submissions into Codable/Sendable StudySession. Seeded randomness and question tokens survive a snapshot round trip; stale callbacks and duplicate completion attempts are rejected.
- The existing iOS review screen uses a protobuf/repository adapter. Its synchronous local persistence boundary remains in place. Missing catalog content now produces an explicit error without dropping assignments. Practice status belongs to the session rather than relying on each caller to pass a flag on every answer.
- Combined Anki answers now stay on the same unfinished item, including after retry delays expand a batch. An item with only one question cannot accidentally credit the next item.
- Compared the compiled legacy session algorithm using injected clock/randomness and stand-in data/services: 960 scenarios across grouping, Anki, order, skipped readings, penalties, practice, retries, deferral, exclusion and wrap-up matched 676,404 state assertions. This is algorithm parity, not proof of real-account sync.
- Durable session-file persistence/resume is not yet connected. The shared state round-trip is tested, but restart recovery must commit session state and pending submissions together under the correct account before SESSION can close.
- Validation: 51 iOS unit/integration tests, 37 shared Swift Testing functions and the native Mac build passed. A dedicated ReviewValidation UI test completed all four sample subjects (five typed questions, including romaji-to-kana input) and reached a 100%, 4/4 summary; the captured screenshot was inspected. This used the fake client and performed no account uploads.
- The screenshot fixture now resolves subject levels from its own data so review eligibility can be exercised without a live catalog. Added stable review accessibility identifiers for regression tests.
