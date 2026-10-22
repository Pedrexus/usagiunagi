# Current modernization tasks

Work lives in `/Users/pedro/Developer/projects/apps/usagiunagi`, on `codex/swiftui-27-curriculum`. Commit to the existing branch; no PRs, pushes or distribution. iPhone Duo stays deferred. The October 22 deletion request supersedes retention of the three excluded owner-edited remnants; their exact source and patch are kept under ignored `.build/Reports/LegacyRemoval-20261022`.

**Primary priority: iPhone/iOS first, one adaptive app.** Develop the main study flow for iPhone and let native SwiftUI controls, available space, Dynamic Type and real service capabilities adapt it to iPad/Mac. Reduce presentation-only OS checks directly; add no platform utility framework or separate desktop feature flow. This steers the full modernization objective, without dropping data, sync, speech or acceptance obligations.

## Completion audit — October 21–22

**Shared app / iPad follow-up:** current iPad lesson teaching/quiz/upload, typed review/upload
and contextual group-selection checks all pass. The active source contains one view
representable, the Japanese input adapter, and no controller representable. Current system
boundaries and their preservation requirements are now listed together in the
[bridge inventory](Implementation/2026-10-22-legacy-removal.md#current-platform-boundaries).
No platform service or feature was disabled to reduce source counts. Physical IME/Watch/
iCloud and full adaptive-window acceptance remain open.

**Accessibility follow-up:** lesson group actions now speak their level/type, and font
download/retry/cancel actions speak the font name. Current largest-text Home and lesson
checks pass. The review geometry test now accepts the selected keyboard's actual first
key instead of requiring an English `a`; the renewed largest-text review journey and
hit-region audit pass with Japanese input selected. Physical VoiceOver and broader audit
coverage remain open. [Scope](Validation/2026-10-22-minimal-working-version.md#accessibility-follow-up).

**Statistics rendered follow-up:** current Mac pace comparison, inline curriculum filtering/
tab restoration and schedule stage/subject breakdown journeys pass. Fresh before/after
captures exposed and verify a small shared dashboard fix: top-aligned cards and an explicit
empty schedule message instead of a blank seven-day plot. iPhone build and enforced lint
pass. This closes that specific layout issue, not real-account calibration or broad
accessibility acceptance. [Receipts](Validation/2026-10-22-minimal-working-version.md#statistics-rendered-follow-up).

**Voice device check and kana conversion:** exclusive microphone ownership,
failure/retry cleanup, same-question hint restart, Watch pause/account/revision fences and
native Watch radical images are repaired. Japanese conversion now normalizes kana/numerals
and can resolve recognizer alternatives without consulting the answer key. Written-text-only
guesses still repeat without grading. Recognized hiragana, katakana and mixed kana retain
their spelling; normalization is internal. Focused shared tests (45 functions), seven hosted
iPhone Watch/image checks, Mac image export and 17 distinct phone/iPad/Mac voice journeys
pass. Real file-fed Mac recognition resolves `1つ` to `ひとつ` using speech alternatives.
Physical paired capture remains open. [Scope and receipts](Validation/2026-10-22-voice-devices.md).

**Today's minimal working version:** local core acceptance passes: 540 shared test functions after the pending-coverage correction,
nine distinct iPhone core journeys, Mac cold routes, separate-process SwiftData reopening,
and iPhone/Mac release-bundle policies. Lessons, typed/voice reviews, account connection,
saved outbox, settings and inline statistics are covered with isolated fixture accounts.
The lesson test now waits for keyboard geometry before tapping; production layout is unchanged.
[Evidence and retained failed trials](Validation/2026-10-22-minimal-working-version.md).
The remaining physical/signed/hosted-CI gates are tracked separately and do not become
accepted merely because local fixture journeys pass. Earlier Mac automation failures below
are historical: the current voice journeys execute successfully on this Mac.

**Legacy removal (current):** the owner requested all obsolete legacy code be deleted. The old SQLite/protobuf database importer and dependency, preference/archive importer, JSON snapshot adoption, Haneke cache adoption, username-based iCloud mistake bridge, excluded UIKit/controller remnants and ClockKit migration bridge are removed. Startup uses the native store directly; WidgetKit and current SwiftUI study flows remain. Existing repository fixtures use native data. The active probe retains native reading/recovery comparisons; its checksum-pinned old writer remains excluded from current targets as historical evidence. Frozen V1 models and minimal Codable receipt declarations remain necessary to open existing native saves and are not alternate runtime paths. Old Tsurukame imports and installed ClockKit face migration are intentionally no longer supported. Validation and remaining acceptance are recorded in [the deletion checkpoint](Implementation/2026-10-22-legacy-removal.md).

Initial deletion validation (historical): iPhone/Watch Debug and Mac Release builds pass; shared/hosted/probe
verification sources compile without execution. Full lint passes 435 files; read-only bundle
policies find no retired library/class symbols. The rule inventory retains 211 findings / 98
rules, and frozen schema/fixture checksums pass. Production Swift is 2,122 physical lines smaller
against the Watch checkpoint. Automated tests remain deferred; no microphone, normal account,
signed services or original-app usability acceptance runs in this deletion pass.


**Apple Watch voice reviews:** the primary Watch screen now runs continuous voice through
the paired iPhone's on-device recognition, shared grader and revision-checked SwiftData/
outbox. One Start action precedes haptics, automatic progression and unclear-answer
repeats; Pause stays in the toolbar. Recording is foreground-only and bounded. No separate
Watch credentials/store or server ASR is added. Series 12's system Audio Intelligence
is researched separately from app APIs. The first manual install catches the unpublished
widget's invalid child identifier; it is corrected without changing shipping phone/Watch
identities. Watch/iPhone Debug, shared Mac Release and scoped checks pass. Manual Series 12
install/launch, visible Start and Settings/return pass; no microphone or review is started.
The inventory is 234 findings / 98 rules with three additional complexity advisories.
Automated tests remain deferred until the end; signed paired-device/audio acceptance
stays open. [Behavior, platform limits and receipts](Implementation/2026-10-22-watch-voice.md).

**Continuous voice review:** one microphone tap now enables inline voice across questions.
Tentative speech is visible, a 1.2-second pause in recognizer updates requests finalization,
and only finalized text goes through the unchanged revision-checked grader/store. Correct
answers start the next capture after a short feedback interval. Following the owner's
no-tap clarification, mistakes show the correction and advance with their penalty intact;
unclear readings repeat automatically, and a single recognizer-supplied kana interpretation
needs no selection tap. Setup/permission and fatal errors still pause. Keyboard use,
end-session dialogs and backgrounding stop the run. Pronunciation autoplay pauses during
voice review. Manual isolated phone checks reach the saved summary without further taps,
retain a deliberate mistake's penalty and verify
correction/typing recovery. Both unsigned Release builds, their packaged-app audits,
scoped formatting and 587 shared Mac test functions pass before the latest instruction.
**The owner now explicitly defers further automated tests until the end; the in-flight
phone lane is canceled, not accepted as a completed gate.** Real-microphone timing remains
unaccepted. Full formatting retains 30 protected-file errors; the rule inventory is
231 findings / 98 rules, including one new nesting advisory in the shared voice controls.
The earlier 61-method old-build run is explicitly canceled after three passes to prioritize this
requested flow; its fourth case records cancellation, not a completed regression gate.
[Behavior, research and validation](Validation/2026-10-22-continuous-voice.md).
The current phone gate declares 69 methods, including the three new voice journeys;
earlier 66-method receipts retain their historical source scope.

**Ownership bugs repaired:** katakana voice uses the mandatory shared audio environment,
and WaniKani settings reads belong to one app-owned task. A canceled-view regression fails
before the repair and passes afterward; overlapping callers, explicit refresh and late
disconnect/reconnect responses are covered. All 580 shared Mac functions, three current
native phone scenarios, both unsigned Release builds and four executable audits pass.
The nine-method native-root baseline also passes on `25a9457b`; its scope stays separate.
One failed native trial catches stale voice-warning wording in the test, then the renewed
voice journey passes with its grading/fallback assertions retained. Full lint remains at
30 protected formatting errors and 230 signals / 98 rules. Five inactive build caches are
removed, recovering about 2 GiB; reports and frozen fixtures stay retained.
[Exact receipts and limits](Validation/2026-10-21-code-audit.md#ownership-audit--october-22).
The planned ordinary 61-method phone lane was canceled as recorded above; the five
URL-driven methods remain separate. The current gate has 69 methods after the voice
additions. Full phone regression and broader acceptance are deferred until the final stage.

**Dense feedback follow-up:** manual onscreen-keyboard grading finds the Correct banner
clipping the next question in short landscape. A first native trial also records a
zero-width question when three notices compete at 250% question size; that failure stays
retained. Tight layouts now use one summary symbol with every notice in its spoken label;
ordinary layouts retain their full text. Question text honors its proposed height, and
an unused audio-notice API is removed. The renewed three-case native run passes without
failures/skips or reported runtime warnings. Inspected captures cover maximum question
size, both orientations, correct/completed/milestone feedback and the revealed header.
All 577 shared Mac functions, both unsigned Release builds and four executable audits
pass. Full lint retains the 30 protected errors; the inventory is 230 findings / 98 rules,
with one fewer long-function signal. [Exact source scope, failed trial and captures](Validation/2026-10-21-code-audit.md#dense-review-feedback--october-22).
The complete 66-method phone gate and the broader acceptance work below remain open.

**Review layout and keyboard verification:** answering keeps the question and response
as the same two `AnyLayout` children across orientation, and portrait feedback gains
scrolling recovery actions. Production falls five Swift lines. All 577 shared Mac
functions, five native iPhone scenarios, both unsigned Release products and four
executable audits pass. Inspection catches a false-positive keyboard assertion: a
keyboard can exist below the screen. The renewed test requires a visible letter key
and full-screen captures. It rejects the hidden keyboard, then passes unchanged after
Device Hub restores software-keyboard display. Both final captures are inspected;
question/prompt/input stay clear, and the draft survives settings, rotation and typing.
The failed precondition run is retained. Full lint remains at 30 protected formatter
errors, the inventory remains 231 findings / 98 rules, and hosted CI cannot fetch its
Mainboard pin. [Exact scope and evidence](Validation/2026-10-21-code-audit.md#review-layout-and-keyboard-verification--october-22).
The full UI/accessibility/device/signed-service gates below remain open.

**Native accessibility follow-up:** the exploratory full iPhone audit finalizes with
three failed cases / 74 issues, including one test-selector mistake. A standalone native
SwiftUI form reproduces three contrast warnings, but no Dynamic Type warning. Captures
and the full failures stay recorded. Scaled/wrapping subject headings, expanding Home
cards, clearer key text, an intrinsic-width lesson counter and one review progress
announcement are implemented. Home navigation and review hit-region checks pass within
the first failed trial; the renewed heading/privacy suite then finalizes with two passes,
zero failures/skips and zero reported runtime warnings. The actual greeting grows from
57.3 to 191 points. Full accessibility and physical VoiceOver acceptance remain open.
[Scope, native control and exact evidence](Implementation/2026-10-21-adaptive-validation.md#native-accessibility-audit--october-22).
The [viewport follow-up](Implementation/2026-10-21-adaptive-validation.md#home-and-review-viewport-follow-up--october-22)
moves the account/vacation header into scrolling Home content and keeps the question
outside the answer's scroll region. Native input uses its intrinsic height; a space-based
fallback keeps the prompt readable at very short heights. Manual isolated iPhone/iPad
checks precede the renewed geometry/draft/grading tests. The lesson comparison also
scrolls within the visible list above its fixed footer and passes its scaling check.
The linked receipt records exact build/test scopes; broader signed/device gates remain.
The newest scan contains 231 findings, including one additional explicit `UIFont` reference
inside the retained Japanese-input adapter. The compact input now honors a standard small
control request; Dynamic Type remains enabled. The earlier 230-finding receipts below
retain their own source scopes. The five failed native trials remain recorded alongside
the final retry.
The normalized final iPhone case now passes: portrait and landscape captures are inspected,
the draft survives Quick settings/rotation/continued typing, and runtime warnings are zero.
Regular landscape grading, 577 shared Mac functions, both unsigned Release builds and all
four executable audits pass within the exact scopes in the linked receipt. Full lint
remains red for the 30 protected formatting errors, and hosted CI still cannot resolve
Mainboard `b34c931`. The full review UI and broader device/accessibility gates stay open.
The complete phone gate declares **66 methods**: 57 `ReviewFlowTests` and nine
`NativeRootFlowTests`. Five review methods need the separate URL-event driver lanes.
The earlier 57-method wording counted only the review class; focused passes do not
accept the complete gate or iPad/Mac interaction.

**Latest keyboard/detail diagnosis:** a standalone SwiftUI form reproduces the notes
frame warning when a keyboard-toolbar button is present, even without a sheet or spacer;
the captured plain-form controls stay clean. This is a scoped simulator/framework
reproduction, and no diagnostic is suppressed. The lesson-note test now shares the
verified keyboard-readiness helper. All information moves into the fixed review tool
strip so it is reachable without scrolling to the end of the details. Both Release
builds, their four executable audits and all 577 shared Mac functions pass on the final
source. The focused privacy/conflict suite finalizes with two passes, no failures/skips
and the retained framework-pattern warning. Full lint still reports only the 30 protected
formatter diagnostics; the inventory remains 230 findings from 98 rules. [Evidence and exact limits](Implementation/2026-10-21-adaptive-validation.md#notes-keyboard-diagnostic-follow-up--october-22).
One unchanged-source conflict case also passes with verbose failure diagnostics disabled,
but still takes 160 seconds; the experiment gives no useful speed benefit. Diagnostic
defaults remain unchanged, and broad UI/accessibility acceptance stays open.

**Latest iPhone navigation follow-up:** warm review/lesson/subject links, held refresh
and all three material-conflict cases now produce passing native bundles. Drafts, hidden
notes, exclusion state and the Stats return destination survive the exercised flows.
The sync observer now initializes from an already-active sync; stale test expectations
and keyboard geometry are renewed without weakening grading or conflict assertions.
The notes keyboard uses native toolbar spacing, but still produces an unresolved
`Invalid frame dimension` runtime warning. A failed viewport-bound experiment is removed.
All 577 shared Mac test functions, both unsigned Release builds and their four packaged
executables pass again. Broader UI/signed acceptance remains open. [Exact run scopes, failed trials and the retained warning](Implementation/2026-10-21-adaptive-validation.md#iphone-navigation-and-refresh-audit-follow-up).

**Latest storage/rule follow-up:** the actual iPhone disk-full matrix now passes notes,
completed reviews and completed reviews adopted from a genuine committed WAL. One producer
and two fresh readers verify all three isolated stores (38/39/39 exact records), original
penalties, one pending answer per review and unchanged source/retained images. The marked
128 MiB image is ejected and removed. [Current evidence and remaining limits](Implementation/2026-10-21-frozen-ios-and-review-focus.md#native-iphone-completed-review-disk-full-matrix).
Mainboard `b34c931` also fixes the onboarding matcher missing `--locked` commands and
crediting task-name prefixes; twelve isolated checks pass. All five CI tool checkouts now
pin that commit. It still needs separately authorized publication. Earlier adoption,
rendered UI and physical/signed acceptance remain open.

**Latest code/rule audit:** [the current receipt](Validation/2026-10-21-code-audit.md) fixes
acceptance of unusable custom API URLs, repairs unprotected formatting/text failures and
adds standard standalone Mainboard tasks plus watch style coverage in CI. Shared Mac and
iPhone suites pass 577 functions each (907 iPhone executions); the unsigned iOS Debug
product builds. Complete lint intentionally remains red for 30 formatting diagnostics
in two protected owner-edited files. The full rule inventory still has 230 review and
maintainability findings, including the 86 existing Swift migration signals; inventory
exit 0 is not a green gate. Hosted CI still cannot resolve the unpublished Mainboard pin.
The broader acceptance obligations below remain open.

**Execution of finish stages 1–4:** the constructor follow-up is committed in the projects repository at `070f3f2a4`: nonthrowing `@Memberwise`, default-backed typed-rule inference, a compiled nonpersistent pilot and an explicit decision to retain the app's native constructors because the unpublished dependency saves only three pilot lines. The weak-capture audit is recorded in [Swift helpers](Swift-Helpers.md). Xcode's supported conversion now removes the separate WatchKit extension target; a SwiftUI `App`/native application delegate, WidgetKit and the installed-face migrator live under `App/Watch`. The storyboard/hosting controller and extension-only plist are removed. No study schema, frozen nested decoder, account protocol or watch packet format changes. Historical-decoder binding remains required before a future stored-schema/payload change, not a reason to introduce that change now.

Stage 2's isolated native manual subset covers Mac Home/review/Quick settings, iPad lesson picking/group select-and-clear/interleaved teaching/rotation, and phone review controls/progress. It finds and fixes the stale group custom action by exposing a separate real selection button, combines progress for accessibility, and caps wide lesson reading width. Final native iPhone/Mac builds are `build-eb8d8d8b957a427c9fa189686fbd874b` / `build-f33eb24aa0c44a3cbde797e52c9530d1`; the final watch build is `build-50907aa2561a41b2bff4c83f656b0374`, all with zero compiler/analyzer errors or warnings. Captures are in `.build/Results/FinishStages-20261021/`. Original behavior is compared against pinned `upstream/master` lesson paging/subject-strip and review focus/previous/settings/wrap-up handlers plus the owner's current screenshots; the original binary is not rebuilt or exercised. No real account/exercise/microphone or signed service is used. Broad accessibility/IME/physical and installed-face acceptance remains open.

Source/config/test work is committed at `43266939`; the current [finish-stage receipt](Implementation/2026-10-21-adaptive-validation.md#finish-stages-14--october-21) supersedes older test-deferred/watch-host statements below. Stage 3 follows the source/manual work: both shared destinations pass 576 functions (887 parameter executions), including the renewed 46-choice iCloud contract, invalid imports, study deferral and device-local exclusions. Projects commit `e55818c5a` adds passing constructor/macro/native SwiftData tests. iPhone regression runs cover pause/draft/focus, Previous/Quick settings, group select/clear, quiz resume, correction/Anki/landscape, native root routes and largest-text review controls. Obsolete selectors are renewed without removing their assertions. Stage 4 still requires signed/physical services and separately authorized publication of the Mainboard pin; the current GitHub lookup returns HTTP 422 with “No commit found.” Earlier source-scoped receipts are not current acceptance.

**Latest visual steering:** the owner supplied seven current WaniKani account pictures and asks for a less bland app with the same useful sections, adapted to Liquid Glass and native SwiftUI. [The design reference](WaniKani-Design.md#october-21-owner-supplied-account-references) owns the mapping: saturated lesson/review actions, forecast, recent mistakes/extra study, level/item progress, recent subject tiles/community and lesson selection/composition/review context. Fresh isolated iOS captures are now authorized by the explicit screenshot request; this does not authorize real exercises, normal-account launches, microphone access or unrelated device/signing work. Existing implementation and final-test obligations remain in the finish order below.

**Latest Tsurukame references:** two additional owner screenshots request denser teaching/review screens and symbol tools at the keyboard. The shared layout now has a full-width question, compact progress/prompt, inline answer check and a SwiftUI tool strip at the keyboard safe area; lesson details put meaning/readings/components before mnemonics with a shorter header and subject strip. The existing Japanese input bridge remains for language selection, marked text and caret behavior. Public anonymous level pages match all 357 bundled display subjects by level/type counts; the preview no longer invents a locked account status. [Compact layout evidence and remaining checks](WaniKani-Design.md#compact-tsurukame-study-follow-up) retain the distinction between browsing data and complete API grading metadata. No source schema, dependency or graded session behavior is changed; automated tests remain last.

**The goal is active; the app is not yet fully accepted.** The app checkout is physically under `projects/apps/usagiunagi`; `codex/swiftui-27-curriculum` is its Git branch, not another folder. Portable settings are committed at `4771355d`; the initial separate `dataclass` source is committed in the projects repository at `88a211843`. The current visual follow-up and its exact evidence are recorded in [WaniKani design](WaniKani-Design.md#current-implementation-and-manual-evidence). Preserve the three protected owner edits. The current Mainboard pin is `fa467e0`.

Implemented source covers the shared SwiftUI app, SwiftData writer and historical import, voice input, charts/curriculum coverage, branding, WidgetKit, API caching, WaniKani settings and 46 portable iCloud preferences. This does not establish complete behavior or signed delivery. The October 22 unsigned iOS/Mac Release builds and four packaged executable audits include the endpoint and initial sync-observation changes; the linked receipts retain the exact shared-test and UI scopes. Scoped formatting passes; the protected-file formatting, notes-keyboard warning and broader acceptance limits remain explicit above. AppIntents metadata notes retain their separate scope.

| Finish order | Remaining work and completion evidence |
| --- | --- |
| 1. Finish source work | Constructor/inference, ownership audit, measured pilot/adoption decision and supported single-target SwiftUI watch conversion are implemented. Retained native bridges have explicit reasons. Keep concrete-model queries and full refresh for non-subject collections until measurements/reset semantics justify changes; no speculative schema/observer abstraction. Bind historical decoders before any future stored payload/V2 change. Physical watch continuity remains stage 4. |
| 2. Compare usability | Isolated phone/iPad/Mac manual subset and current iPhone native regressions compare pinned original source/owner screenshots. Selection actions, combined accessible progress, wide reading width and native pause are corrected. The original binary, broad high-contrast/IME/image-radical/physical accessibility and normal-account window restoration remain unaccepted. Mac UI automation now runs: eight distinct lesson/review journeys and hide/activate plus cold-link checks pass across scoped runs. Saved-window restoration and physical services remain open. |
| 3. Run final tests | Shared, macro/runtime, fixture app, scoped phone UI, historical-value and bounded full-volume checks run through Mainboard. The actual iPhone note/review/committed-WAL review matrix passes rollback, same-revision/question retry and two fresh-process reopens of every store. Earlier adoption and wider failure combinations stay open. All five URL-driven behavior cases now finalize passing bundles despite long test/reporting delays. Trace the repeatable notes-keyboard frame warning; broader phone/iPad/Mac suites remain open. Reduce Motion is an explicit unconfigured-device skip. |
| 4. Close external acceptance | Local unsigned build/resource and identifier readiness are checked. Still required: signed iCloud/App Group/Keychain and paired-watch continuity; physical microphone/IME/audio/background/storage behavior; permitted real-catalog performance/statistics calibration and icon/device acceptance. Hosted Actions cannot resolve the unpublished `fa467e0` pin. No signing, publication, push or distribution is performed. |

No new feature is needed to finish this list. iPhone Duo remains deferred, the dismissed Coverage popup stays closed, Parquet is retired and read-only AI/intents remain optional. Do not replace completion work with speculative schema normalization, a new platform abstraction or another cache layer. The detailed request table and migration gates below remain authoritative for exact scope.

## Resume checkpoint — October 21

**Reusable dataclass request:** the authorized library lives at `projects/packages/dataclass`, with typed rules, struct/final-class construction, strict/open Codable and native SwiftData validated saves. Constructor-only generation, safe typed-rule inference, a measured nonpersistent pilot and 16 final Mac test functions are implemented. The three-line pilot saving does not justify adding the unpublished dependency to this app. Composing our macro with `@Model` requires the documented private uncallable `Never` initializer; ordinary SwiftData models do not. The library does not intercept autosave/imports or change frozen models. Publication, wider platform verification and any future schema-safe app adoption remain separate. [Context and boundaries](Swift-Helpers.md#owner-authorized-dataclass-package). Expanded WaniKani/app settings ownership and private sync are implemented and locally tested; signed delivery and the remaining storage/usability gates stay on this ledger.

The usability pivot does **not** complete or cancel the storage work. This is the authoritative work ledger; [Migration.md](Migration.md) owns the phase/gate contracts, and the request table below retains every other workstream. Keep completed implementation, scoped local evidence and outstanding acceptance separate. The overall goal remains active. No new storage implementation was started during the UI pass.

**Storage resume history:** the UI pivot left storage at `c491febe`, the bounded Mac APFS disk-full task; `20920687` is the preceding shipping-storage change, simplifying typed startup comparison. UI commit `2ffc6b39` changes only three shared views and their documentation. The resumed work adds the [independent historical decoder gate](Implementation/2026-10-21-frozen-ios-and-review-focus.md#independent-historical-value-decoders) and [completed-review disk-full check](Implementation/2026-10-21-frozen-ios-and-review-focus.md#completed-review-disk-full-transaction). Resume from these checkpoints rather than repeating the migration or regenerating the baseline.

- [x] SwiftData actor, native queries/outbox and production generation opener are implemented; FMDB and the old writer are removed. The SQLite3/protobuf importer is now removed. The public Core Data validation boundary still protects existing native SwiftData stores.
- [x] Frozen V1, ten model types and the independent 38-record/two-account fixture are retained. Recorded corruption, metadata, permissions, cancellation and changed-source cases preserve data. The twelve-phase iPhone simulator protocol verifies completed-review/WAL durability, pre-answer-commit interruption/retry and abrupt verification/candidate-opening recovery.
- [x] Actual bounded Mac APFS disk exhaustion before note mutation and before commit preserves the complete baseline, original revision and upload state. Free-space retry succeeds, and two fresh processes verify the result. Mainboard owns the image lifecycle. [Exact scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#actual-apfs-disk-full-save-and-recovery).
- [x] Actual Mac disk exhaustion after the completed-review/session/mistake mutations reach the real save boundary rolls back the entire prepared state and old revision. Retrying the same question/revision queues one answer with the original mistake penalty; two fresh processes restore all 39 records. The fixture fills residual 4 KiB blocks as well as large chunks; a small review could otherwise still save. This is an additional G7 case, not full migration acceptance.
- [x] Actual Mac disk exhaustion during journal-free and committed-WAL first adoption, after the read-only SwiftData verification attachment, refuses further preparation; exhaustion after writable candidate attachment refuses final selection-file publication. Fresh processes retry with a different candidate, preserve every abandoned artifact and the retained/original images, verify all 38 records, commit an exact pending note edit and pass two further process reopens. [Ten-case protocol and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#committed-wal-disk-full-matrix).
- [x] Native iPhone simulator access to Mainboard's bounded APFS image now passes through the fixture-only host and production opener, comparing every field of the 38-record baseline. The shared image lifecycle ejects and removes the successful image. This is access/adoption preflight, without pressure or disk-full acceptance. [Scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-bounded-volume-access-preflight).
- [x] Actual iPhone Simulator note-save disk exhaustion now refuses the write, preserves all 38 saved records, retries the same expected revision after free space returns and passes two fresh process reopens. Mainboard owns the bounded APFS image and required Actions task. [Exact protocol and scope](Implementation/2026-10-21-adaptive-validation.md#actual-iphone-simulator-disk-full-save).
- [x] Actual iPhone completed-review ENOSPC now passes with both journal-free and genuine committed-WAL source adoption. The real dirty save includes the answer/session/mistake update; refusal preserves all 38 prepared records and the original revision. Same-question retry keeps the original penalty, queues one unattempted answer with fresh identities, and two fresh processes verify all 39 records and unchanged source/retained families. The same three-host matrix repeats the note case. [Current receipt](Implementation/2026-10-21-frozen-ios-and-review-focus.md#native-iphone-completed-review-disk-full-matrix).
- [x] Actual iPhone simulator final selection-file publication ENOSPC passes for journal-free adoption. Four fresh hosts verify Cocoa/640 at the exact selector URL, unchanged preparing selection/source, different-candidate recovery, exact 38-record state and pending-note write, then two further reopens. [Scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-final-selection-publication-disk-full).
- [x] Actual iPhone simulator disk exhaustion after read-only verification attachment and before final selection publication passes for both journal-free and committed-WAL sources. All four cases preserve source/retained/abandoned artifacts, retry with a different candidate and verify the exact pending-note write across four distinct hosts. See the October 22 validation receipt, StorageSpace.NKZTwA.
- [ ] Extend actual iPhone disk-full coverage to earlier source capture and physical failures. The passing verification/publication and note/review/WAL save cases do not prove those boundaries. Use only isolated bounded fixtures; never fill the host filesystem or present an injected failure as actual disk exhaustion.
- [x] Actual Mac pre-answer-commit interruption now exits from the real dirty completed-review save boundary for both ordinary and WAL-backed adopted stores. Two fresh processes restore the entire prepared 38-record state; a separate retry preserves the original mistake penalty and queues one answer, followed by two exact 39-record reopens. [Scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#completed-review-pre-commit-interruption). No production fault hook or schema change is introduced.
- [x] Actual Mac SIGKILL after a complete selected-generation file becomes visible preserves ordinary/WAL source adoption. Two fresh readers restore all 38 records before any app write; the first answer/note write survives two further exact 39-record reopens with the same selection. [Scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#published-selection-process-interruption). The observation identifies a visible publication boundary, not an instruction inside rename/fsync.
- [x] iPhone 18 Pro / iOS 27 simulator pre-answer interruption now runs across four fresh test hosts: exit 86 at the dirty completed-review save, reopen the exact 38-record prepared state, retry with the same question/revision and original penalty, then verify all 39 committed records through two new actor openings. Source/retained images and selection remain unchanged; exactly one unattempted answer is pending. [Protocol and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-pre-answer-commit-interruption).
- [ ] Complete actual abrupt mid-copy/inside-publication interruption, physical-device iPhone pre-answer interruption, Data Protection/power-loss and wider failure combinations. Simulator process durability does not prove those physical cases. These differ from the passing Mac visible-publication and pre-commit cases, cancellation and post-commit restarts.
- [x] Preserve the original writer's 67-file domain/storage source closure and original baseline reader in hashed, compressed test-only archives. Mainboard independently compiles those modules; two fresh Mac processes restore all 38 records/ten models/fifteen Codable attributes twice each. Changed source bytes and an extra source file are refused before opening. The canonical store/manifest/writer and shipping schema remain unchanged; standalone Actions declares the same gate.
- [ ] Before any V2/property change, bind the preserved historical nested decoders into the actual production upgrade path and close the applicable G7 upgrade/recovery gates. Source preservation and an unchanged-schema Mac read do not prove an evolved-schema migration or iPhone decoder acceptance. P5 model/query refinement and P6 observer simplification remain planned, subject to measured need and parity; neither is accepted from the existing V1 receipts. Keep direct concrete-model queries and avoid another storage abstraction layer.
- [ ] Measure real-catalog/device startup, reads, answer commits and memory; the warm-cache synthetic Mac startup comparison is only a scoped benchmark. Signed original-install/Keychain/container upgrade continuity and a permitted source/export route remain separate gates.

When storage resumes, first reconcile those unchecked items with the [G7 contract](Migration.md#required-test-traceability), then extend the existing Mainboard task/probe for one bounded missing case before considering a model change. Preserve the frozen writer/store/manifest and all unrelated owner edits.

**Other work remains tracked:** iPhone-first UI/usability and original-app comparison; adaptive iPad/Mac/keyboard/accessibility acceptance; remaining native-input/watch/service bridges; real voice capture; credible chart/calibration work; complete permitted levels 1–3 mock data; settings/media, notifications/background, sync/account recovery and signed services; final watch lifecycle/installed-face upgrades; branding/icon/store acceptance; cleanup/rules/dependencies, Swift Testing/final regressions and hosted Actions. Each retains its implementation and remaining work in the request table below. New read-only intents/AI tools are optional P7 scope, not an approved answer-grading path. iPhone Duo stays explicitly deferred; the dismissed Coverage popup stays closed. Existing device-access restrictions and the no-push/no-PR/no-distribution instruction remain unchanged.

## Current implementation and evidence

**Private iCloud app preferences:** [the separate one-model SwiftData store](PrivateICloud.md) now covers 46 logical portable choices: review, lesson and subject preferences, WaniKani source choices, selected fonts/voices and scalar display choices. Device-specific keyboard/audio/notification/download configuration stays local. Per-field versions retain disjoint edits without publishing new-device defaults. Imported learning changes wait while any scene is studying; display changes can apply immediately. Typed publishers and SwiftUI revision observation replace the provisional reverse callbacks/weak captures. Application types and configuration explicitly distinguish iCloud from WaniKani sync. The native private schema and all study-store `.none` configurations stay unchanged. Container registration, signed delivery/account-switch tests and rendered acceptance remain open; no live iCloud access is claimed.

**Latest settings/helper steering:** the [WaniKani integration](PrivateICloud.md#wanikani-baseline-offline-cache-and-explicit-edits) places six controls in a WaniKani group and app-specific choices in an App settings group on the same page. User edits persist locally and sync after a 600 ms debounce, with inline progress/confirmed status and retained pending edits on failure. There is no separate WaniKani page or Save button. The account/endpoint-fenced SwiftData cache and independent app source controls preserve existing local/imported choices; new preference groups can follow WaniKani. Source metadata lives outside frozen Codable handoffs; its portable iCloud implementation is now present. Automated tests stay at the end after implementation/manual checks. The owner additionally requests modern initializer/validation research, simpler models, more native synthesis and a careful weak-reference audit. [Swift helpers](Swift-Helpers.md#latest-initializer-validation-and-ownership-requests) records the completed constructor/inference implementation, measured pilot and 16 passing Mac test functions. App adoption is conditional on a larger measured benefit and reproducible publication; broad platform qualification remains open. Preserve frozen schemas/decoders, unrelated Patos edits and all earlier acceptance restrictions.

The WaniKani transport retains expected-account GET/partial PUT, unknown order preservation, edited-field response checks and a separate token-permission denial. Only actual user edits create pending intent; startup defaults/iCloud reads never do. An uncertain attempt is not replayed automatically; a fresh GET can confirm it without another PUT. Study consumes separate lesson/review/Extra Study audio, supported order and lesson batch, and completed-review SRS changes independently of current-question stage style. Paused queues keep their captured options. Disposable native demonstrations cover coalescing, pre-network persistence, failed saves, actor/model reopens and lost responses; native builds and scoped lint are recorded in the [integration checkpoint](Implementation/2026-10-21-frozen-ios-and-review-focus.md#wanikani-settings-integration). Current-source automated API/race/UI tests, real-account permission behavior, signed private iCloud delivery and all earlier migration/service gates remain open.

**iPhone volume-access preflight:** Mainboard now shares its existing bounded APFS image lifecycle between the ten-case Mac task and a fixture-only native iPhone access task. Explicit task environments select the backend even when the caller supplies the opposite value. The iPhone production opener restores all 38 exact baseline records on the mounted image, preserving source bytes; the image is ejected and removed on success. Actions declares the same preflight after its twelve-phase iPhone restart. No iPhone disk-full, hosted execution or shipping-source change is claimed. [Current evidence](Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-bounded-volume-access-preflight).

**Ten-case bounded storage recovery:** the existing Mainboard APFS task runs its five note/review-save and adoption/selection points against both journal-free and committed-WAL sources. The WAL seed must leave the main DB unchanged, populate a WAL and change exactly one pending note/revision; all other saved fields remain exact. Both opening points retain the failed candidate, retry in a fresh process and preserve every abandoned artifact. Each case passes two further reopens. The final task emits ten receipts, ejects its exact device and removes the successful image and WAL source. [Current evidence](Implementation/2026-10-21-frozen-ios-and-review-focus.md#committed-wal-disk-full-matrix) retains the [earlier five-case probe corrections](Implementation/2026-10-21-frozen-ios-and-review-focus.md#disk-full-first-adoption-and-final-selection). No shipping Swift/schema, owner files or app UI change. iPhone, earlier capture/activation, abrupt mid-copy/publication, power-loss, historical-decoder/V2 and all other acceptance gates remain open.

**Mainboard native environment:** the standalone manifest now declares one Mac Xcode default while preserving explicit shell/CI selection. Native parser, SwiftUI rules, formatter and SwiftLint run through the existing locked/no-install task runner, which applies declared variables as well as PATH. Full current source checks pass without a manual export; alternate/missing-Xcode and strict-rule controls preserve selection and failures. Both current unsigned Release builds and all six packaged-binary/name/icon/resource/linkage checks pass with zero native compiler/analyzer warnings/errors. [Exact scope and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#mainboard-native-environment-and-current-release-checks). No Mainboard package/pin, lock, app Swift, schema, owner edit, signing or global Xcode preference changes; hosted CI and rendered/physical acceptance remain open.

**Constructor cleanup and compiler policy:** the first native-synthesis pass removes six redundant UI helper initializers and their unnecessary public surface, saving nineteen physical production lines. Keep constructors for cross-module public APIs, classes, validation, identity and historical decoding; no macro dependency or model change is introduced. Xcode now inherits one Swift 6/warnings-as-errors policy on both SDKs, including the UI runner, and all nine Shared targets use SwiftPM's native warning policy. A redundant UI teardown wrapper is removed to fix its non-Sendable XCTestCase capture. [Rationale](Architecture.md#native-initialization-and-synthesis) and [final receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#native-synthesis-and-compiler-warning-policy) record both build-for-testing passes, 561 shared functions on each platform and both fixture-only app-host suites. The watch build passes with its existing Interface Builder storyboard warning. UI execution, Release and other open acceptance gates are not claimed by this change.

**Shared UI API cleanup:** a [second caller/initializer pass](Implementation/2026-10-21-frozen-ios-and-review-focus.md#shared-ui-initialization-and-api-surface) removes 24 more forwarding constructors and the unused standalone sign-in wrapper. Internal settings, bindings, builder content, summary and recovery views now use native synthesis; state-seeding/validation/service constructors remain. The active Account form and its cancellation owner are unchanged. Production falls another 175 physical lines, with no model, test or dependency changes. The native SwiftLint initializer rule now runs through existing Mainboard enforcement; positive/negative controls retain required public, private-storage, transforming and class initializers. Both build-for-testing actions, shared Mac/iPhone suites and fixture app hosts pass. Rendered usability and all broader gates remain open.

**SwiftUI 27 follow-up:** verified Apple's AsyncImage HTTP caching/request/session APIs and State/ContentBuilder changes against current primary docs and the installed SDK. Radical WebPage creation now uses a lazy State default. Existing builders already gain the unified implementation; keep the avatar import/decoding/clear-cache behavior and SVG renderer. [Rationale and initialization caveat](Architecture.md#swiftui-27-image-loading-and-state-lifetime). Both Debug builds pass with zero compiler/analyzer warnings or errors (`build-1b1aa5dbe3dd4766b9ee0afc8761f092` iPhone, `build-aa33d22a76c544d68f46f0c1b1274b84` Mac); focused rules pass. This is compiler/initialization evidence, not rendered acceptance or a measured build-time speedup. No storage, grading, API-cache or access gate changes.

**API data and offline caching:** the owner supersedes the earlier Parquet requirement. Authenticated URLSession → SwiftData now reuses saved subjects with server `updated_after` watermarks; the complete merged catalog still reaches the existing importer. Endpoint/access-level changes, incomplete/invalid caches and a seven-day reconciliation deadline force complete subject reads. Watermarks and content commit together in the existing cursor dictionary; V1 is unchanged. The unused Parquet derivative and its separate developer catalog-export workflow are retired. Keep the native 357-item display preview and deterministic tests for disconnected development. The shared app has no external package dependencies; retain the app's sole SwiftProtobuf dependency for original-install imports. [Current native API/tool choice and validation](Implementation/2026-10-21-frozen-ios-and-review-focus.md#api-subject-caching-and-native-networking-cleanup) records 561 shared functions on Mac/iPhone, 858 iPhone executions, both app hosts and the full storage checks. Other account collections still refresh completely; their incremental/reset handling and real-account/device performance remain open. No account/exercise was accessed.

**Current usability priority:** compact WaniKani-colored Home rows, disclosed level-up scenarios, clearer review actions with a bottom Continue/grading inset, and quieter Stats typography remain. The next [study-navigation refinement](WaniKani-Design.md#lesson-progression-and-compact-review-headers) adds native lesson Next/Start quiz and an inline study title while keeping chips/swipes/keys; short/wide reviews retain their meaning/reading strip below the subject instead of splitting the question column again. Only two shared views change in this follow-up. Both Debug builds pass without compiler warnings, all 556 shared functions pass, and scoped lint passes. Earlier hosted iPhone/Mac and storage results retain their own source scopes. [Reference provenance](WaniKani-Design.md#october-21-usability-refinement) distinguishes historical original screenshots from the pinned source's later hero. Actual iPhone-first visual, keyboard and accessibility acceptance remains open because device/computer access was denied; no UI execution was attempted and no prior open migration/service gate is closed.

**Updated toolbar guidance:** the [native toolbar follow-up](WaniKani-Design.md#adaptive-native-toolbar-priorities) uses shared `visibilityPriority` for lesson progression and review Voice; secondary font/settings controls move first when space contracts. Lesson progression uses a text title, and Home's toolbar is explicitly scoped to top-level content instead of pushed study routes. Apple marks the new explicit overflow-menu API unavailable on macOS, so no platform fork is introduced for it. Both current Debug builds and scoped rules pass; this is compiler/source evidence, not rendered overflow or keyboard acceptance. Storage/API/voice/statistics and the other open workstreams remain unchanged.

**Shared hosted unit checks:** one `AppTests` target and folder now replace the two hosted bundles. Six files moved byte-for-byte; the obsolete target/plist and 172 configuration lines are removed. All function identities and parameter cases retain their verdicts on Mac (83 functions/160 executions) and iPhone (95 functions/172 executions), each with the declared restart-task skip. Ten UIKit-input and two WatchConnectivity functions remain iOS-only. Mainboard owns `test-app-ios` / `test-app-mac`, with parent proxies and matching required Actions steps. Mac Actions reuses `UnifiedMac` products and allows 45 minutes for resolution, unit and UI gates. Both Release builds and six-binary policies pass after consolidation. Source inventory remains 259 parsed files with zero gaps/context issues; shipping Swift, models, frozen persistence sources and dependency versions are unchanged. See the [single-target checkpoint](Implementation/2026-10-21-adaptive-validation.md#one-hosted-unit-test-target).

**Shared scene follow-up:** foreground sync now starts only from the common active-scene task; the duplicate Mac-only preparation start is removed. Task identity tracks both scene phase and service readiness so successful startup Retry can activate the same worker without a phase change. Common native window defaults apply across platforms; Mac-only launch/restoration APIs retain their required guard. Both Release builds, regular iPhone regression (95 functions/172 executions plus the declared restart skip), 18 shared Mac sync tests, focused lint and six-binary bundle policies pass. Native rendered Retry/activation/window sizing remains open. See the [scene checkpoint](Implementation/2026-10-21-adaptive-validation.md#shared-scene-activation-and-window-defaults).

The latest adaptive follow-up lets review progress, feedback, retry, information and grading controls choose a row or column from their actual content width. One private `ViewThatFits` helper replaces text-category-only branching and duplicate feedback layout, removing ten production Swift lines overall. The answer field stays outside the alternatives, retaining its single input/focus owner. Lesson-strip buttons now have at least 44-point touch targets. Home retains the shared native Search/Settings toolbar and automatic Saved work/Refresh placement. Current iPhone compilation, regular non-UI regression, native Mac Release and focused Mainboard lint pass; exact current counts/scopes follow below. Compact/wide/large-text/keyboard and rendered toolbar checks remain open; no new OS branch or platform utility layer is introduced.

The lesson-selection footer now follows the same content-fit policy: count and Start action remain in a row when their natural widths fit, otherwise they stack. It no longer chooses that arrangement solely from an accessibility text-size category. Keep the footer's native touch-friendly position and the existing lesson selection/start semantics. This small presentation change does not alter grading, storage or sync. Its compiler/lint evidence and remaining rendered checks are recorded in the [adaptive checkpoint](Implementation/2026-10-21-adaptive-validation.md#content-fit-lesson-selection).

**Current iPhone storage gate:** Mainboard's mandatory twelve-phase `native-store-restart` preserves graceful/abrupt completed-review durability, WAL state and interrupted verification/candidate opening. Its four new pre-answer phases observe the real dirty save boundary, reopen the exact prepared 38 records, retry the same question/revision with the original mistake penalty, then verify all 39 committed records through two actors. Source/retained images and selection remain exact. Four intentional exit-86 runner failures are guarded explicitly; the other eight phases pass normally. This is simulator process evidence; physical-device interruption, actual mid-copy/inside-publication, disk-full, Data Protection and power-loss acceptance remain open. [Full protocol and receipts](Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-pre-answer-commit-interruption) retain the earlier eight-phase source scope as history.

**Current stage: scoped local correctness, remaining implementation and acceptance.** The shared UI cleanup passes 561 shared functions/72 suites on Mac and iPhone, with 858 iPhone executions and no skips/failures. Regular fixture-only `AppTests` passes 95 functions/172 executions on iPhone and 83/160 on Mac; each has one declared skip requiring the separate restart task. Current build-for-testing actions also compile the UI runners in Swift 6 without executing them. The twelve-phase restart, earlier Release/six-binary audits and historical catalog-export receipts retain their exact source scopes; export itself is retired. Zero-warning app summaries do not erase the retained watch-host warning. Mainboard's exact `Skip Message` reader preserves the positive-passing-case requirement. Rendered and signed/physical acceptance remain open.

The [current checkpoint](Implementation/2026-10-21-frozen-ios-and-review-focus.md) records native adaptive controls, migration refusal/retries, real file-fed speech results, current incremental Release iPhone/Mac builds and six-binary linkage/resource inspection. Two obsolete app asset catalogs are retired: 37 files / 3,531,556 source bytes, preserving the active layered icon. Native summaries have zero compiler warnings; older clean-restoration/watch/cache receipts keep their source scope, including the retained watch deprecation. Rendered phone/iPad/Mac usability, real capture and signed-device services remain open. Earlier [sync/curriculum correctness evidence](Implementation/2026-10-20-original-flow.md#sync-and-curriculum-correctness), protobuf, watch-cache and Mainboard receipts remain recorded below and in the checkpoints.

Earlier adaptive and scrolling checkpoints remain historical in the [original-app comparison](Implementation/2026-10-20-original-flow.md). The current follow-up enables native sidebar adaptation from iPhone tabs, shares the Refresh command with iPad keyboards, moves lesson Back into the native toolbar and removes an unused audio capability flag. The October 21 follow-up removes the Mac-only minimum window frame and its wrapper, leaving the shared layout to handle compact space. It also removes the never-populated blocking-progress flag: cached study and Settings remain available during atomic refresh. No platform utility framework is added. Device Hub access was denied, so rendered phone/tablet/window, keyboard and largest-text acceptance remains open.

**Current acceptance access:** the owner's explicit current screenshot/design request authorizes isolated iPhone manual inspection. The latest design receipt records that subset; it does not authorize normal-account exercise, real microphones, signed services or broader automated UI execution. Earlier restricted device/browser access must not be bypassed. The [watch launch trial](Implementation/2026-10-20-widgetkit.md#october-21-launch-handoff-trial) retains the legacy extension entry point; its provisional source changes were fully reverted. Historical Release/watch/bundle receipts keep their exact source scopes and do not establish launch or signed-upgrade acceptance.

| Request | Current implementation | Work left |
| --- | --- | --- |
| Rename/fork/icon | `Pedrexus/usagiunagi`; localized 兔鰻/usagiunagi. Main/watch icons compile only the shared layered kanji document. Current static default iPhone/watch exports and compiled Mac fallback are checked; source art and Mac fallback remain byte-exact after catalog retirement. Release bundles retain the expected display names/icon metadata | On-device home-screen/Dock/watch and appearance-mode acceptance, owner-controlled signing/identifiers and store distribution/listings; nothing released |
| One Swift/SwiftUI app | iPhone/iOS is the reference. One shared root/model/store; native tabs/sidebar, semantic toolbars/search/forms/reordering and space/text-size signals adapt larger screens. No device-idiom or size-class fork in active UI; Mac-only minimum window restriction removed | Rendered phone/iPad/Mac layouts and hardware/soft keyboard acceptance; Japanese input adapter and native service/scene boundaries remain documented; Watch views use SwiftUI and the installed-face migration adapter is removed |
| WaniKani style and usability | The latest owner-supplied references now guide saturated pink/blue action cards, native grouped Home/progress, recent subject tiles/community, colored component tiles, lesson group selection/batching/interleaving and contextual review prompts. Shared system typography, SF Symbols and native glass controls remain. Fresh iPhone renders and a manual five-subject interleaved teaching sequence are recorded in the design receipt; the Home refresh-task identity loop is fixed. Earlier original-source comparisons retain their exact scope | Complete compact/wide, dark/high-contrast/Dynamic Type, keyboard/focus/IME, image-only radicals, selection/Clear/paused quiz and review feedback/correction/summary checks; iPad/Mac rendering and broader original-flow parity remain open. Current scoped manual evidence does not close them |
| Review/lesson functionality | Native synonym+correction transaction, previous subject, original-conjugation highlighting, continue without forced reveal, early completed-item summary and exact-character feedback. Restored lesson audio, wrong-answer editing lock/retry, summary Return/current-level labels and Home shortcuts. Short/wide reviews preserve one answer column/input owner. Previous return restores focus. Anki tap/Return opens assessment without default credit; advanced actions share one body. Actual-field locked Cut/Backspace and editable Backspace tests pass | Final native regression/IME/caret/draft/Anki/wrap-up/exclusion/summary and device acceptance. Previous return, combined Anki correction/reassessment and wrap-up pass current iPhone UI execution; see the October 22 review parity receipt. Scoped synthetic Mac Home Return/retry/Voice fallback focus is observed; full iPhone/iPad keyboard delivery remains open. Mac refresh intentionally uses Command-Shift-R |
| SwiftData and migration | Native actor/outbox/generation adoption/recovery; direct model queries; unchanged V1. Legacy database import is removed. Typed comparison removes one wrapper/five production lines; Mac synthetic 10,000-subject median reopen 1.029→0.884 s. Mac and iPhone simulator pre-answer-commit interruption/retry preserve the original mistake penalty and exactly one pending answer. Mac visible-selection interruption preserves adoption and subsequent writes. Five bounded Mac APFS `ENOSPC` points cover note/review saves, verification-stage adoption and final selector publication. Fresh retry preserves abandoned candidates and exact original/retained data, with first-write and process-reopen checks. The iPhone note/review/WAL save and journal-free final-publication ENOSPC checks pass, including exact retries and fresh-process reopens. Mainboard owns volume lifecycle and cleanup. Independent historical sources/decoders compile and reopen the unchanged baseline | Actual mid-copy/inside-publication and physical iPhone pre-answer interruption; iPhone disk-full earlier capture/verification and committed-WAL opening combinations; Data Protection/power loss and wider combinations; production historical-decoder binding before V2; real-catalog/device performance |
| Recent mistakes and sync | Observed-event fencing, bounded retry, 24-hour wire projection, durable binding/revocation and lifecycle wiring. App-owned refresh now publishes committed state even when its waiting screen cancels; both refresh paths have a failing-before/passing-after regression. Account/credential fencing, form cancellation and saved-note preservation pass in the full suites. Connected auth incidents remain acknowledged/deferred correctly | Signed shared iOS/Mac KVS namespace, real account/device delivery and wider rendered account recovery |
| Voice reviews | Shared Apple continuous capture/transcript flow, automatic answer/advance/retry, native sizing, immediate start and typing fallback. Eighteen scoped voice UI journeys pass across iPhone/iPad/Mac, including Mac hide/reactivate and keyboard fallback; physical capture remains unverified. Optional installation requests decide whether a download is needed. Real Mac file-fed Japanese alternatives can form `ひとつ` while the primary stays `1つ`. Reading corrections reuse the existing input; a native menu offers at most six distinct kana combinations from final recognizer segments, without answer-key lookup or kanji conversion. Raw text stays unchanged until explicit choice/edit; normal Check answer still grades. Core/controller and actual iPhone input-binding tests pass | Physical iPhone models/microphone, capture sequence, latency, interruptions/audio routes and rendered iPhone/iPad/Mac Voice/menu flows. Synthetic files and model tests do not establish human recognition/pronunciation accuracy or end-to-end capture behavior |
| Credible statistics/plots | Swift Charts, pace/focus scenarios/backtesting, school/Jōyō and estimated JLPT. Official Kanken 4/3/pre-2 membership independently matches the pinned PDF (313/284/328 additions); exact hashes, samples, cumulative sets and four milestone denominators pass. Unsupported SRS values no longer inflate coverage. Pending-review subjects have a separate Awaiting sync segment and per-target count; shared tests, historical store reopening and rendered iPad acceptance pass. Focus prioritizes recurring trouble, then WaniKani level | Full-account calibration and rendered chart acceptance. Character coverage cannot establish exam passing readiness |
| API cache and offline mock data | API → SwiftData subject deltas merge with saved catalog values before replacement; cursor/cache scope, weekly reconciliation, exact pending work and rollback/reopen checks pass. Parquet and its one-off catalog export workflow are retired; diagnostics remain. Native 357-item display preview and deterministic tests remain | Assignments, materials, statistics and level history use complete downloads rather than incremental cursors. Saved-store reset reconciliation passes while retaining pending recovery content. Measured performance and real-account/offline acceptance remain open. HTTP conditional requests remain optional measured work, not another required cache layer. Preview remains display-only |
| Settings ownership and private iCloud | One Settings page groups six WaniKani controls and app choices. Debounced updates retain account/origin fences and pending intent. The independent private iCloud schema covers 46 portable choices with validation/conflicts and study deferral; device-specific configuration stays local. Current shared tests pass an independent exact allowlist, invalid imports, no-echo persistence, multiple-scene deferral and device/account exclusions. Native phone settings/timing/diagnostic sharing passes. The API URL editor uses a form sheet after its Cancel alert failed; the complete editing journey and summary now pass on both iPhone and iPad. Study/outbox and recent-mistake KVS contracts are unchanged | Register the owner's container, inspect signed iPhone/Mac entitlements and verify cross-device/background/account-change delivery. Real-account API permissions and broader rendered settings/media acceptance remain open |
| Native settings/media/services | Shared forms/owners; typed diagnostics, fonts/audio/images, endpoint validation, notifications and logout; asynchronous background scheduling; single-target SwiftUI watch lifecycle, four WidgetKit families, atomic snapshot, retained background tasks; the retired ClockKit face migrator is removed | Broader Mac settings/media equivalence and physical notification/background/audio/watch behavior; App Group registration/signed access, old-extension cache and face-upgrade acceptance; signed Keychain upgrade and iCloud namespace |
| Trim/reorganize/dependencies | Retired duplicate UIKit/SQL/writer/API/generated sources/assets and Hippolyte; native tests preserve assertions. Removed both unused app asset catalogs, 37 files / 3,531,556 source bytes and eight project-reference lines; the shared icon and font preview resources remain. SwiftProtobuf and its plugin are removed. Current Release inspection covers all six packaged Mach-O files/all architectures, with no retired-library matches | Final resource/rendering acceptance. Fresh archived-source Release iPhone/Mac restoration passes at the committed package pin; global caches were retained. Symbol/linkage absence does not prove optimized-out package provenance. The old importer, protobuf dependency and excluded owner remnants are now removed |
| Swift constructors, validation and ownership | Thirty native initializer removals remain. Reusable `dataclass` adds nonthrowing construction, safe typed-rule inference and validated native SwiftData saves. Current Mac runtime/persistence/macro tests pass. A measured two-field nonpersistent pilot saves three lines; the app retains native constructors rather than an unpublished dependency. Weak lifetime boundaries are audited and existing cancellation/account fencing tests pass; iCloud names are explicit | Reproducible publication and larger measured benefit before app macro adoption; broader deallocation/physical-service acceptance. Do not apply the neighboring-macro `Never` workaround to ordinary models or rewrite frozen schemas for boilerplate savings |
| Swift Testing | After the pending-coverage correction, shared Mac tests pass 540 functions (109 + 17 + 171 + 243). The removed four functions tested only the dead upload coordinator. Hosted iPhone passes 85 functions/154 executions and Mac 67/134, each with one declared separate-process skip. Current iPhone Previous-return, combined Anki and wrap-up UI journeys pass. Earlier larger counts are historical and include retired paths; see the current validation receipt | Physical keyboard/IME, full VoiceOver and Reduce Motion, broader native rendering, signed iCloud and paired Watch acceptance remain open. Scoped Mac UI automation now runs successfully; earlier initialization failures do not describe every current run |
| Mainboard rules/tools | Fourteen Swift rules, formatting/SwiftLint, offline guidance and typed inventory. `apple bundle` covers six packaged binaries and app resource/name policies. Exact native `Skip Message` diagnostics are supported while empty/all-skipped results and unknown verdict-less nodes remain failures. Apple/bundle/CLI focus: 323 passed; complete isolated suite: 1151 passed, 11 declared skips, 3 existing warnings. Configured typing: zero diagnostics with unchanged suppressions; scoped Ruff/format pass. Previous strict new-module and literal/CUPTI receipts retain their scope | No new ignores or weaker settings. Optional whole-project strict-preset experiment remains separate. Historical invocation/toolchain/disk-full and interrupted-suite receipts remain recorded. Linux/solver/remote prerequisites and tool publication remain separate |
| GitHub Actions | Bounded Mainboard Apple lanes, pinned resolution/reports, unsigned iOS/Mac Release, twelve-phase iPhone restart, ten-case Mac APFS recovery and the seven-phase iPhone ENOSPC matrix (note/review/WAL saves plus verification and final publication with journal-free and committed-WAL sources) in a dedicated job. Root proxies and standalone manifest share these checks. Prior fresh-source restoration and URL-driver receipts retain their scopes | All five Mainboard checkouts pin `fa467e0`; the latest GitHub lookup returns HTTP 422 “No commit found.” No hosted run, publication, push or distribution is performed. A local gate does not establish hosted or signed acceptance |
| Known issues | Six shared-test warnings and invalid PNG CRC remain resolved. The converted watch builds without the removed storyboard/hosting warning. Current compiler/analyzer summaries are clean; AppIntents metadata skip messages remain separately scoped. Historical frame/QoS/stale-cache diagnostics remain recorded | Broader rendered/physical acceptance and signed watch/cache continuity; physical-device accessibility remains unaccepted; current scoped Mac automation and largest-text Home checks pass. No global warning suppression. User dismissed the Coverage popup; do not reopen it |
| Reported launch/reopen crashes | The first pasted report is the earlier Tsurukame SwiftUI navigation trap at October 19 01:16; the [review-exclusion receipt](Validation/2026-10-19-review-exclusion.json) retains its correlation and later scoped checks. The second report is Simulator SpringBoard, not this app, as recorded in the [quality receipt](Validation/2026-10-20-swift-quality-and-migration.json). No speculative restoration workaround is retained | Final current-source launch, reopen and window-restoration acceptance on Mac/iPhone, followed by inspection of any new matching app report. Neither successful compilation nor the separate persisted-payload corruption fix proves the original navigation failure cannot recur |

The [original WidgetKit checkpoint](Implementation/2026-10-20-widgetkit.md) is historical. Current Watch voice and legacy-removal receipts supersede its installed-face migration adapter, which has been deleted. Four WidgetKit layouts and the shared snapshot contract remain; physical paired-device and signed acceptance are still open.

The owner approved application on October 20; the former automatic-review blocker is resolved. Production startup uses the generation opener, with canonical Mac/iOS compiler evidence and the correction for unordered handoff preference Sets. Only explicit memory-store fixtures were opened for the scoped Mac comparison; no normal account/store or production migration ran. Remaining rendered comparison, broader migration/failure and decoder compatibility, physical/signed services and full final acceptance stay open. No further V2/schema redesign is justified by current source evidence; independently preserve historical decoders before any future payload/V2 change. Signed services, real catalog data and hosted publication retain their prerequisites. Browser access to the open WaniKani page was declined; no workaround was attempted.

The [adaptive validation follow-up](Implementation/2026-10-21-adaptive-validation.md) records the remaining API-specific OS boundaries, clean Release iPhone/Mac restoration from committed sources and a widget mirror validation fix. Its new 15 watch-cache test functions/25 invocations pass on Mac and hosted iPhone without touching normal defaults or App Groups. A disposable persisted-payload corruption probe first exposed a real SwiftData framework trap; that historical failure remains recorded. The production generation owner now validates all fifteen Codable paths through public read-only Core Data binary projections before SwiftData reads. Both representative damaged payloads now throw safely, preserving original/retained/selector data and generation membership. Intact/WAL/fresh-install/process reopens and all 551 shared functions pass after the guard. Wider G7 and real-catalog/device performance remain open; the safeguard adds an account-wide startup read, not another storage layer.

The [iPhone adoption and review-focus checkpoint](Implementation/2026-10-21-frozen-ios-and-review-focus.md) extends that evidence without changing V1 or the opener. The frozen iPhone simulator test compares every record/field and preserves subsequent note edits through actor reopens. The selected-store matrix exercises all fifteen Codable paths, including a populated review issue, and all nine required NULL mutations. Its 26 safe refusals preserve selected DB/WAL as well as original/retained/selector data; only SHM bookkeeping may change. All ten current root persistence phases pass, including selected metadata and first-adoption retries. A narrow Previous-return focus fix, native adaptive controls and shared voice-correction input preserve the iPhone-first review flow; on-screen execution remains open.

## Execution order

1. Production implementation and the cleanup pass have reached final acceptance. Fix concrete failures found during acceptance before rerunning affected checks; retain the removal manifest and documented platform responsibilities.
2. Compare the completed app with original Tsurukame's pinned source/usability baseline. Preserve the quick lesson/review rhythm and WaniKani visual language; record intentional native adaptations and fix regressions. Use only isolated fixtures, never real exercises.
3. The owner’s tests-last instruction applies: this is now the final acceptance stage, with implementation repairs preceding their regression checks. Complete native Mac/iPhone/iPad flows, Swift Testing, native store restarts, iCloud compatibility, rules/format, Debug/Release/resources/linkage and reproducible dependencies. Do not overlap jobs on the same UI device or derived-data directory. Record exact source revisions; historical passes are not substitutes. Legacy import is deliberately retired, not a current acceptance target.
4. Commit final work to the existing branches. Physical/signed/full-account gates and unpublished CI prerequisites remain explicit if they cannot run locally. Do not mark the whole modernization complete while required evidence remains.

The [migration specification](Migration.md) retains M1–M8, P0–P8 and G1–G12 contracts, frozen fixtures, nineteen writer mappings and historical parity IDs. Its older tests-before-deletion sequence is superseded by the owner's latest implementation-first order, not by a claim of successful acceptance.

## Historical acceptance

- [Read-only importer independence](Validation/2026-10-20-legacy-importer-without-fmdb.json): nine hosted functions and 24 bootstrap functions; original importer fixtures do not use FMDB.
- [Frozen native store baseline](Validation/2026-10-20-native-store-baseline.json): pinned writer, 38 records/ten model types/two accounts; not a future model upgrade.
- [Typed diagnostics and parity](Validation/2026-10-20-native-diagnostics-and-parity.json): 508/69 shared scope, dirty-save rollback/reopen and native sharing/audio acceptance with exact limits.
- [Catalog and persistence rules](Validation/2026-10-20-native-catalog-and-persistence-rules.json): 513/71 scope and earlier native catalog results/failures; warnings remain scoped.
- [Last accepted checkpoint](Validation/2026-10-20-native-practice-parser-and-upgrade-probe.json): 523/72 shared scope, final native catalog/practice/settings evidence, parser/Release/disposable upgrade experiment. It accepts neither current deletion nor the new persistence/cloud implementation.

## Latest cleanup checkpoint — October 22

Full hosted iPhone/Mac regressions and the exact-method Mainboard execution safeguard
are recorded in [the current validation receipt](Validation/2026-10-22-minimal-working-version.md#full-hosted-regression-and-test-selection-safeguard).
The duplicate historical complication scheme is removed. Continue auditing unused
runtime declarations; preserve frozen Codable/store contracts and live native bridges.
Physical paired Watch voice, signed iCloud synchronization, broader accessibility and
hosted CI publication/acceptance remain open. No push or distribution was performed.
The follow-up Core audit removes the unreferenced upload coordinator and its private
regression suite; the active SwiftData upload tests remain and pass. Final shared tests
and all configured Mainboard lint checks pass after removal. Frozen schema and fixture
checksums are unchanged. Remaining historical Codable identities are required by existing
native stores, and are not candidates for unversioned deletion.

Home study-action contrast: explicit adaptive primary text fixes two faint section headings.
The scoped light/dark audit passes and a negative control reproduces the original heading
failure. Wider contrast, the timing row under the translucent tab bar, inconsistent captures
around native contrast auditing, and system-enabled Reduce Motion remain open; see the
[contrast receipt](Validation/2026-10-22-minimal-working-version.md#home-study-action-contrast).

Timing-row follow-up: native contrast passes after normal scrolling in both appearances,
with full-frame checks above the tab bar. Wider Home contrast findings remain open;
prioritize visible light-mode section headings and explanatory text, then distinguish
lower controls from glass overlap. Physical iPhone remains unavailable; owner connection
and developer-team questions are pending. No signed/device/iCloud acceptance is claimed.

Visible Home contrast follow-up: corrected faint light-mode headings/help text and dark-mode
subject names while retaining WaniKani icon/bar colors. One consolidated audit now rejects
all contrast findings fully inside the unobscured initial/scrolled Home viewports; unknown
frames fail and outside-frame findings are recorded. It passes both appearances and Mainboard
checks. Lower Home sections, other pages, Reduce Motion and physical VoiceOver remain open.
[Current evidence](Validation/2026-10-22-minimal-working-version.md#broader-visible-home-contrast).

### 2026-10-22 — Home lower-page acceptance

Completed the light/dark Home contrast sweep through the community link, including lower
SRS and recent-activity sections. Native audit and Mainboard lint pass; final captures reviewed.
See the minimal-working-version receipt for explicit disabled/occluded-control exceptions.
This supersedes the open lower-Home contrast check for this fixture only.

### 2026-10-22 — Additional dead-code/reference audit

Rechecked production method/type references and resource generation inputs. No additional
unused production subsystem established after the previous legacy and UploadCoordinator removals.
Removed obsolete Mac 32-bit Xcode warning metadata; corrected current development instructions
that still described deleted protobuf/importer targets. Retained required platform callbacks,
IME support, native-store fixtures and resource generators. Runtime behavior unchanged.

### 2026-10-22 — iPhone foreground reopening

The existing native draft/settings/pause journey now also backgrounds and reactivates the app
from the reading field and from open settings. Both transitions preserve the unsubmitted
Japanese draft and current navigation state. One native test passes without skips/failures;
Mainboard lint passes. See the minimal-working-version receipt for exact scope. Process-death,
Mac window-restoration and physical-device acceptance remain separate open requirements.
Reconciled stale top-level test counts, removed Watch bridge references and automation status.

### 2026-10-22 — Mac reopening and cold-link acceptance

Two current native Mac tests pass: hide/reactivate preserves the draft/question and one study
window before normal pause/submit/completion; cold subject/review/lesson links each open one
window. Replaced the wrong-bundle process precondition with the tested app's stopped state,
and updated the stale prompt expectation. Mainboard lint passes. Actual saved-window
restoration after termination remains open; fixture cold links intentionally ignore saved state.

### 2026-10-22 — Mac study parity and assessment follow-up

Eight fixture journeys now have passing evidence across retained runs: discard, retry draft,
extra study, wrap-up, lesson teaching/quiz/pause/completion, typed exclusion, Anki review
exclusion and Anki lesson exclusion. Native split-button menu selectors and contextual prompt
expectations are corrected; exclusion explicitly asserts zero credit. Mainboard lint passes.
Mixed earlier suite failures remain recorded in the current validation receipt.

Open: Mac primary assessment confirmation dialog omits advanced exclusion/synonym actions
in the observed hierarchy, while the native split-button menu provides exclusion. Investigate
this UI difference; passing menu tests do not establish parity of the primary dialog.

### 2026-10-22 — Assessment presentation repaired

Closed the Mac primary-assessment action omission above. A single shared SwiftUI presentation
now shows all available actions, adapts to compact sheets and anchors to the control on wider
layouts. Mac cancellation/synonym/exclusion and iPhone/iPad incorrect-then-correct journeys
pass; exclusion still awards zero credit. Mainboard lint passes and the Mac capture is reviewed.
No platform branch, storage change or grading change was introduced. See the adaptive
assessment section of the current validation receipt for the retained failed trials and limits.

### 2026-10-22 — Largest-text assessment accessibility

Fixed a reproduced iPhone accessibility issue: assessment labels clipped and Cancel could
not be reached at Accessibility XXXL. The shared view now scrolls, wraps labels and supports
expanded sheets. Native largest-text reachability/cancellation and ordinary grading pass;
the Mac synonym/exclusion regression also passes. Before/after captures inspected and
Mainboard lint passes. Broader physical VoiceOver and adaptive-window acceptance remain open.

### Pending coverage follow-up — October 22

Fixed offline pending-review kanji being mislabeled “Not started”: transient outbox IDs now drive
an “Awaiting sync” coverage segment and SRS withheld-count note. Shared regression tests (540)
and Mainboard lint pass; serialization bytes and frozen sources remain unchanged. Still required:
historical on-disk reopening/schema verification and rendered coverage UI check. Full iPhone
acceptance session 17816 is testing pre-fix commit 9cfb5ead; do not attribute it to this fix.
See the minimal-working-version validation record for exact logs and limitations.

Pending-coverage historical verification now passes at `60d2ab59`: exact 38-record/10-model
baseline and named-schema fresh-process/WAL preservation probes. Rendered coverage verification
remains next after the running iPhone suite. Its Reduce Motion test explicitly skipped because
the simulator setting is disabled; this does not satisfy real Reduce Motion acceptance.

Prepared the pending-coverage rendered regression in
`NativeRootFlowTests/testPendingReviewCoverageShowsAwaitingSyncInsteadOfNotStarted`, reusing the
existing uncertain-review fixture. Each target now states its awaiting-sync count explicitly,
so tiny chart segments are not the only indication. Mainboard lint passes. This new UI test
has not run: serialize it after session 17816 completes, then inspect its retained screenshot.

### Current acceptance follow-up — October 22

- Pending coverage passes the new iPad regression and inspected screenshot; compact iPhone
  verification remains open.
- The ongoing pre-fix full iPhone suite exposed an API endpoint editor that did not close on
  Cancel. The final SwiftUI form-sheet replacement passes cancel/validation/save/persistence/reset
  on iPad, and compiles on Mac with zero warnings. Mainboard lint passes. Failed alert approaches
  are not retained. The UI helper now scrolls the visible Settings form rather than disabled Home.
- After session 17816 finishes, collect its full result and run the repaired developer endpoint
  and pending-coverage tests on iPhone. The suite's Reduce Motion skip remains unaccepted.

The three offline-audio journeys pass on iPad without production changes. The full iPhone run's
enable-toggle failure in download/Keep/deletion still needs a focused rerun (its retry and
voice/cellular cases passed). Seven unreferenced generated experiment caches were removed,
freeing approximately 2.6 GiB while retaining active products and validation/frozen evidence.

### iPhone acceptance reconciliation — October 22

The 30-minute full run is terminal (124), with an incomplete result bundle: its log records
57 passes, three failures and one Reduce Motion skip. Focused continuation finishes nine of
11 cases; corrected endpoint text replacement and current-level summary assertions then pass
in a separate two-case iPhone bundle. All failed/unfinished methods now have scoped passing
execution, totaling 68 distinct logged passing phone methods across runs, not one green full
suite. Keep the failed/interrupted evidence. CI limits are now 40 minutes per main UI lane and
60 minutes per matrix job; hosted publication remains blocked by the unpublished Mainboard pin.
The new coverage chart is rendered and inspected on iPhone/iPad; full accessibility remains open.
Audio and lesson-order retests pass without production changes. The iPad endpoint/summary run
(session 79517) still needs its final result; it has long idle waits. See the validation receipt.

### 2026-10-22 — Final obsolete build-setting cleanup

Removed unused explicit compression linking and local C-header search paths from Debug and
Release; corrected stale importer comments. Current declaration/resource checks found no
additional safely removable implementation. Required offline behavior, saved-data identities,
IME integration and historical verification fixtures remain. Mainboard lint and generic iOS
simulator build pass; see the legacy-removal receipt. The iPad endpoint follow-up passed in
its log, but summary automation timed out with an incomplete bundle; retain that acceptance gap.

### 2026-10-22 — iPhone activation disk-full recovery

Closed the journal-free final selection-file publication case using real bounded APFS
exhaustion and four fresh test hosts. Focused and integrated seven-phase matrix runs pass;
original/retained data, abandoned artifacts and an exact subsequent note write are verified.
The existing Mainboard task owns pressure, receipt checks and successful image cleanup.
No production storage change or new abstraction. Earlier capture/verification, committed-WAL
opening and physical-device failure cases remain open in the storage ledger above.

### 2026-10-22 — iPad endpoint and summary acceptance complete

After a non-erasing iPad simulator restart, the unchanged missed-summary journey passes
alone and after the API endpoint edit/reset journey. The full two-test sequence has a
completed green result bundle; its earlier timeout remains historical evidence. The fresh
summary capture was inspected for visible content and clipping in portrait/light/default
text. No app change, extra delay or weaker assertion was introduced. Broader adaptive,
accessibility and physical-device acceptance remain open. See the current validation receipt.
Reconciled the top-level shared-test count and storage/Actions table with the latest evidence.

### 2026-10-22 — Accessible review assessment presentation

Fixed the iPad largest-text assessment popover that clipped actions and could not be scrolled
by the acceptance test. Accessibility text sizes now use a native sheet; ordinary sizes keep
the popover. Both share the same actions with no added platform checks. The unchanged
max-text test passes on iPhone and iPad, and the Mac normal-size advanced-action flow passes.
Fresh phone/tablet captures were inspected; Mainboard lint passes. Reduce Motion, VoiceOver
and broader accessibility/layout acceptance remain open. Exact failed/fixed receipts are in
the current validation record.

### 2026-10-22 — Live statistics clock and iPad adaptive checks

Fixed stale due counts/calendar buckets when Statistics remains open by supplying SwiftUI's
minute timeline date to the existing metrics calculation. Saved snapshots and network behavior
are unchanged. A live iPhone fixture verifies 0→1 due with the original snapshot timestamp;
11 Mac statistics tests pass including local-midnight rollover. Mainboard lint passes.

Three iPad adaptive checks pass: maximum-text Home navigation, Home progress/refresh through
rotation, and landscape review/draft/settings/completion. Screenshot inspection led to a
stronger post-settings keyboard-visibility assertion; that final landscape check also passes
and its stable capture was inspected. No extra delay or platform branch was introduced.
These are scoped local checks; real-account calibration, VoiceOver/Reduce Motion and physical
services remain open. Exact source scopes and bundles are in the current validation receipt.

### Mac voice fallback acceptance

All five current continuous Mac voice journeys pass together after cleanup. A new sixth
case verifies hide/reactivate during listening, the unchanged reading question, refusal of
an unresolved spoken kanji answer, keyboard fallback and a 100% completed summary. Full
Mainboard lint passes 436 files. [Exact scope and receipts](Validation/2026-10-22-voice-devices.md#current-source-mac-interruption-and-keyboard-fallback).
No production change; physical microphone/Watch, signed services and termination/window
restoration remain open.

### iPad Home light/dark contrast acceptance

The Home contrast audit now uses native content/navigation geometry instead of requiring
an iPhone bottom tab bar. iPad and iPhone both pass the full light/dark sweep through the
community link. The lower iPad captures are visually checked; full lint passes. Production
UI is unchanged. [Failure, repair and exact scope](Validation/2026-10-22-minimal-working-version.md#adaptive-ipadiphone-home-contrast-audit).
Other screens, high-contrast settings, landscape, VoiceOver and Reduce Motion remain open.

### Upcoming reviews local-clock repair

Fixed the detailed forecast retaining future-hour counts after a review becomes due.
The shared view now refreshes its local availability calculation each minute and on the
existing snapshot data revision, clearing stale errors after successful loads. An unchanged
regression fails before the fix and passes afterward; the existing breakdown/Back journey
also passes. Full lint passes. [Exact evidence](Validation/2026-10-22-minimal-working-version.md#detailed-forecast-follows-local-time).
No persistent schema, API request or grading change. Full-account calibration remains open.

### Hosted test-selection parity

Updated all five Actions Mainboard pins to the locally used `fa467e0`, so hosted runs also
reject a passing bundle that omits an explicitly requested test. All 85 isolated Apple
checks and app lint pass. The exact new SHA is still unavailable on GitHub (HTTP 422).
Publishing the prepared Mainboard branch requires owner approval; no push has occurred.
[Evidence](Validation/2026-10-22-minimal-working-version.md#hosted-workflow-includes-the-test-selection-safeguard).

### Watch wording and full Mac statistics/catalog group

Fixed the shared microphone localization overriding Watch's paired-iPhone explanation.
All four compiled Watch translations and localized names are verified; Watch build and
full lint pass. [Resource evidence](Validation/2026-10-22-voice-devices.md#watch-permission-localization-correction).
All seven Mac statistics/catalog UI cases pass after the shared forecast repair. The earlier
incorrect selector was rejected by Mainboard and is retained as failed evidence. Physical
capture, signed services, hosted publication and real-account calibration remain open.

### Broader iPhone acceptance in progress

At source `88ff3ed5`, the full configured iPhone UI lane is running with its 2400-second
bound, covering ReviewFlowTests and NativeRootFlowTests. The five URL-driven methods use
the separate existing event lanes; Reduce Motion remains subject to the actual device setting.
Log: `.build/Results/iPhone-Acceptance-Final-20261022.log`. Execution session: `2185`.
This entry records an active run, not a passing result; inspect its live handle before any restart.

Reconciled stale Swift-helper instructions against the existing package STATUS, constructor
showcase and `dataclass-tests-first.log` (12 runtime/persistence plus four macro functions).
The implemented pilot is not future work. No macro dependency or frozen model rewrite was added.
