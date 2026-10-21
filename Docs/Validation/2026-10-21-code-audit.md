# Code and Mainboard audit — October 21

The audit starts at `08976b01` on `codex/swiftui-27-curriculum`. The three existing owner
edits are preserved. This is a source, rule and automated regression audit; it does not
close the outstanding rendered UI, signed-service or physical-device acceptance gates.

## Corrected behavior and workflow

- API settings accepted base URLs that the request layer subsequently refused: credentials,
  queries, fragments and dot/traversal path segments. Shared normalization now rejects them
  before replacing the working client or clearing its preference source. Tests cover raw
  input, client reconfiguration and account/model behavior, including encoded traversal and
  preservation of the original transport, credentials, account and preference revision.
- Full lint found 1,532 formatter diagnostics in 13 Swift files and six missing final
  newlines. Eleven unprotected Swift files and all six text/resource files are repaired.
  Two test continuation loops and an overlong comment needed explicit manual corrections;
  assertions and frozen data remain intact. Formatter-only wrapping increases physical
  line counts; this is not a claim of reduced application logic or LOC.
- The standalone manifest now provides `setup`, `lint`, `test`, `build` and `typecheck`.
  `test` is the shared Mac suite, also used by Actions. `typecheck` uses the same native
  iOS Debug build as `build`. Other app, watch, recovery and UI tasks remain necessary.
  CI now includes `App/Watch` in its strict formatter/SwiftUI scope.

## Current evidence

All paths below are relative to `.build/Results/`, except the full lint report.

| Check | Result and receipt |
| --- | --- |
| All kept Swift parses | Complete 446-file repository scope, with the parser applied to its Swift subset; zero failures. `CodeAudit-SwiftParse-20261021.log` and final full lint repeat |
| Expanded formatter/SwiftUI scope | 333 files, zero failures; `CodeAudit-FormattedFinal-20261021.log` |
| SwiftLint | 252 files, zero failures; `CodeAudit-SwiftLint-20261021.log`; repeated in final full lint |
| Complete repository lint | Still exits 1: exactly 30 formatter diagnostics in protected `App/AnswerChecker.swift` and `App/Features/Catalog/LegacyCatalogViewController.swift`; no other step fails and no files are rewritten. `.build/Reports/CodeAudit-FullLintFinal-20261021.json` |
| Shared Mac tests | 577 functions across four test targets, all pass after final test-source edits; `CodeAudit-SharedTestsMacFinal-20261021.log` and the actual `test` task in `CodeAudit-TestTask-20261021.log` |
| Shared iPhone tests | 577 functions / 907 executions, zero failures, skips or reported runtime warnings; `test-652a59798a7b40fc9b71e856b9b9ac7f.xcresult` and its `.tests.json`; `CodeAudit-SharedTestsIOS-20261021.log` |
| iOS Debug product | `build-e0bb21e1e5ed4b2686fe0a0ea7072250.xcresult`, successful native simulator build, zero compiler/analyzer warnings/errors; `CodeAudit-AppBuildIOS-20261021.log`. The optional AppIntents metadata tool still notes no framework dependency. |
| Reformatted probe manifest | Native SwiftPM evaluates its original executable target successfully; `.build/Reports/CodeAudit-ProbeManifest-20261021.json` |

The iPhone run finalized successfully after a long reporting delay. This does not resolve
the earlier incomplete UI automation runs. Expected permission-denial/storage failures
printed by fault-injection tests are not failing tests. No live account, exercise,
microphone permission, normal-account app launch or signed iCloud request is used.

## Findings retained for review

The complete Mainboard scan applies 98 rules and reports **230 findings**, rather than
establishing a green gate (`CodeAudit-AllRulesFinal-20261021.log`). `analyze check` is an
inventory command and exits 0 even when it reports findings; actual lint/gate verdicts above
remain authoritative. The 14 Swift/Objective-C rules account for **86 migration signals**:
7 platform imports, 1 representable, 1 Objective-C selector, 5 SQLite imports, 18 native UI
references, 15 frozen Codable model properties, 7 container owners and 32 SQL calls.
These are retained Japanese input/system-service boundaries, historical import, explicit
store owners and disposable corruption/recovery probes, including native test code.
They are not evidence that FMDB or an Objective-C implementation has returned.

The other 144 findings are 117 overlapping complexity/nesting signals, 25 folder signals,
one upstream-history signal and one formal onboarding-readiness signal. Complex upload,
recovery, grading and view-builder branches need targeted review with their behavioral
contracts; this audit does not split them into speculative abstractions. Folder signals
include required Xcode/asset-catalog structures and ignored/transient cache directories.
Two obsolete empty preview directories were removed locally; required Apple paths and
historical evidence were retained. The missing lifecycle-task signal is now resolved;
formal onboarding readiness is still reported rather than suppressed.

GitHub still returns HTTP 422, “No commit found,” for the pinned Mainboard
`b72cd6fdd7870842a0cd5a7517231d26e5123eff` (`CodeAudit-CIPin-20261021.log`). Hosted Actions
cannot proceed until that prerequisite is published with separate authorization.
No PR, push, signing or distribution is performed.

The frozen `StudySchemaV1.swift` SHA-256 remains
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.
Frozen writer archives/store and historical decoders are unchanged. UI usability,
physical storage/voice/watch continuity, signed iCloud and broader acceptance remain
tracked in [TASKS](../TASKS.md).

## Navigation follow-up

The later [iPhone navigation/refresh audit](../Implementation/2026-10-21-adaptive-validation.md#iphone-navigation-and-refresh-audit-follow-up)
renews stale UI expectations and keyboard geometry, initializes observation of an
already-active sync and adopts native keyboard-toolbar spacing. Warm links, held refresh
and the three conflict cases finish passing native bundles. The focused lesson quiz
also passes inside the separately recorded failed two-test trial. All 577 shared Mac
test functions, both current unsigned Release builds and four packaged-executable audits
pass again. A repeatable notes-keyboard `Invalid frame dimension` runtime warning remains
unresolved; passing test booleans do not establish warning-free UI acceptance. An
ineffective viewport-bound experiment is removed. Whole-repository lint still fails
only its 30 protected-file formatter diagnostics; the full rule inventory remains
230 findings from 98 rules. No migration signal or runtime warning is suppressed.

The current Actions prerequisite is Mainboard `b34c931d776a93d502a0d53061366ae898be5840`,
now pinned by all five checkouts. `NavigationFinish-MainboardPin-20261022.log` rechecks
GitHub and still records HTTP 422, “No commit found.” This supersedes the older pin/readiness
checkpoint above; no hosted execution or publication is claimed.

The [next diagnostic pass](../Implementation/2026-10-21-adaptive-validation.md#notes-keyboard-diagnostic-follow-up--october-22)
reproduces the frame warning in a standalone SwiftUI form with one keyboard-toolbar
button, without app modules, a sheet or a spacer. Its plain-form controls stay clean in
the captured unified logs. This establishes a simulator/framework reproduction, not a
physical-device result or an Apple-confirmed fix. The app keeps its native control.
The same pass corrects a missed quiz-submit tap in the test harness and moves All
information out of the scrolling content into the fixed review tool strip. The linked
receipt retains each failed trial, source scope and final verification result.

The final-source privacy/conflict suite passes both cases with no failures/skips, while
retaining the known keyboard-toolbar runtime warning. All 577 shared Mac functions,
both unsigned Release products and their four executable audits pass on that source.
The fresh `NotesWarning-FinalFullLint-20261022.log` still fails only 30 protected-file
formatter diagnostics; `NotesWarning-FinalAllRules-20261022.log` still inventories 230
findings from 98 rules. The three owner-file hashes and frozen schema remain unchanged.

## Native accessibility follow-up — October 22

The [native audit and scoped fixes](../Implementation/2026-10-21-adaptive-validation.md#native-accessibility-audit--october-22)
retain three failed full-audit cases / 74 issues and an independent native-form control.
Subject headers now scale and wrap, key text has stronger contrast, Home cards can grow,
and review progress has one spoken count. The lesson picker identifies its list/footer;
the test helper scrolls above the fixed controls. The final heading/privacy suite passes
both cases without failures/skips or reported runtime warnings. Measured heading height
grows from 57.3 to 191 points. All 577 shared Mac functions and both unsigned Release builds
pass on the current source; the linked receipt owns exact scope and failed trials.

The full accessibility gate remains open: captures expose an oversized fixed Home account
header and an answer-focus path that scrolls the review question out of view at large text.
Passing taps and hit-region checks do not accept those layouts. Full lint still fails only
the 30 protected formatter diagnostics, and the inventory remains 230 findings from 98
rules. GitHub still refuses the pinned Mainboard commit with HTTP 422; no publication or
hosted execution is claimed.

## Review layout and keyboard verification — October 22

Starting from `eea734c3`, answering keeps the question and response as the same two
`AnyLayout` children across orientation. Feedback/recovery actions scroll in portrait
as well as landscape. Production changes only `ReviewScreen.swift`, removing five net
Swift lines; grading, persistence, dependencies and platform branches are unchanged.
Isolated manual largest-text checks retain a typed draft through rotation and reach
Reveal answer by a touch scroll. The earlier Home/header fixes retain their own
[viewport receipt](../Implementation/2026-10-21-adaptive-validation.md#home-and-review-viewport-follow-up--october-22).

All following paths are under `.build/Results/` unless otherwise stated.

| Check | Current result |
| --- | --- |
| Shared Mac suite | 577 functions pass (108/8/207/254); `StableInput-SharedMac-20261022.log` |
| Five native iPhone scenarios | `test-85b311f0793d4ec0aa3ec47576567da7.xcresult`: five passes, no failures/skips or reported runtime warnings; incorrect reveal/override, landscape grading, Back/draft, exact-match settings and largest-text rotation |
| Unsigned Release products | Mac `build-bed34f78ea5f44cb83ffe4f9d3ece865.xcresult`, iOS `build-61de075b02f74c10b1e5c8dccf242373.xcresult`; zero compiler/analyzer warnings/errors |
| Release bundle audits | `StableInput-ReleaseMacBundle-20261022.json` and `StableInput-ReleaseIOSBundle-20261022.json`: one Mac plus three iOS/watch/widget executables, zero violations |
| Full lint and rules | `StableInput-KeyboardProofFullLint-20261022.log`: 447 files, no rewrites, only the same 30 protected formatter errors. `StableInput-KeyboardProofRules-20261022.log`: 231 findings / 98 rules; inventory exit 0 is not acceptance |
| Hosted Actions prerequisite | `StableInput-MainboardPin-20261022.log`: GitHub still returns HTTP 422 for Mainboard `b34c931d776a93d502a0d53061366ae898be5840`; no publication |

Inspection of the five-pass run's exports finds no visible software keyboard. That run
does not establish onscreen-keyboard geometry, despite a present keyboard accessibility
element. The renewed helper requires a nonempty letter-key frame inside the window,
records geometry on success/failure, and captures the entire composited screen rather
than only the app window. The stricter run `test-32c01a80f74f4be7ac3d73c035d7be83.xcresult`
fails this precondition; Device Hub independently shows the hidden keyboard during
cleanup. Its frame export places the keyboard at y=891 and its A key at y=952, below
the 874-point window (`StableInput-KeyboardProofFailure-20261022/83F382B0-17C9-4AAA-A45A-70B6A1B319CF.txt`).
Device Hub's native Toggle Software Keyboard command restores a visibly presented
keyboard before the unchanged-source retry. That retry,
`test-7d6ea3c7978a4b38936faff990ce3546.xcresult`, passes with no failures/skips or reported
runtime warnings. Both full-screen exports are inspected in
`StableInput-VisibleKeyboardCapture-20261022/`: portrait
`6A5DC54C-CF75-4013-972B-ADFD4D6F4A3B.png`, then landscape
`100CABE8-08F7-495A-A213-5B5B963C3C61.png` with `draft retained` and a visible keyboard.
The geometry exports place the keyboard at y=590 in the 874-point portrait window and
y=222 in the 402-point landscape window. Question, prompt and input stay above the
controls/keyboard without intersecting them; visible-key, draft/settings, hit-region,
rotation and continued-typing checks pass. The new assertion is unchanged between the
failed and successful runs; both remain retained. Source hashes are recorded in
`.build/Reports/StableInput-KeyboardProofSource-20261022.sha256`.

The protected owner-file hashes, frozen V1 schema, historical writer archives/store and
decoders remain unchanged. The whole 57-method review gate, final-source iPad/Mac
interaction, physical accessibility/IME/voice, signed iCloud/watch continuity, real-data
performance/calibration and the other [tracked gates](../TASKS.md) stay open. No normal
account, real exercise, microphone permission, PR, push, signing or distribution is used.

## Dense review feedback — October 22

Starting at `93b12956`, isolated manual grading with the onscreen keyboard and largest
Dynamic Type finds the Correct banner pushing the next question beneath the controls
in short landscape. Moving its symbols beside the question fixes that first state, but
the expanded native trial catches three simultaneous notices squeezing the question to
zero width at 250% question size. Preserve `test-1a3c2f14138c48e8ac8983bf146df1f5.xcresult`
and `DenseReview-CandidateCapture-20261022/262C3027-0997-43C8-BE93-910C976F1B4F.txt`:
the question width is 0, while feedback occupies 159.7 points. Its PNG
`2F98EE8C-B7A6-49FB-A944-A0ECE6250739.png` and Device Hub observation agree. The run stops
at that failure; it does not verify the later portrait/revealed states.

Tight layouts now show one summary SF Symbol, retaining every enabled notice in one
spoken label. Ordinary layouts retain the individual notices. One private typed tuple
collection supplies both presentations, preserving the preference and SRS-estimate
conditions. Question text honors the proposed height instead of forcing its preferred
height. The unused optional audio-notice parameter/path is removed after checking both
callers; active audio notices remain in the native review host. Only one production
view changes, adding 24 net Swift lines; this is a usability correction, not LOC savings.
No persistent schema, grading, dependency or platform branch changes.

The renewed `test-4eb54532ebd94ce3aed103b8b4109952.xcresult` passes all three selected cases,
with no failures/skips or reported runtime warnings: regular landscape grading, independent
feedback settings with draft preservation, and the expanded largest-text journey. The
latter selects 250% through the real settings picker, retains the draft, grades meaning
and reading, verifies completion/milestone labels and geometry in both orientations, and
opens the revealed header with Continue reachable. Inspected exports under
`DenseReview-SummaryCapture-20261022/` include landscape completion
`5BBFD719-5B74-40A2-A613-1B10642706FB.png`, portrait completion
`AAD88884-580B-4473-A49B-E344EAF9F6B4.png`, and revealed header
`11B8C471-7097-4437-87B9-6E84167112A1.png`. The keyboard and question remain visible in
the answering captures; the revealed glyph scales within its header. This does not
accept all large-type detail scrolling or the complete accessibility gate.

All paths below are under `.build/Results/` unless stated otherwise.

| Check | Result and receipt |
| --- | --- |
| Shared Mac tests | 577 functions, all pass; `DenseReview-SharedMac-20261022.log` |
| Unsigned Release products | Mac `build-dcee5cb7f4874a79a7858f0989913fac.xcresult`; iOS `build-df6b7223813c4af8ae5a6babdb649f7a.xcresult`; zero compiler/analyzer warnings/errors |
| Bundle audits | `DenseReview-ReleaseMacBundle-20261022.json`, `DenseReview-ReleaseIOSBundle-20261022.json`; four executable audits, zero violations |
| Full lint | 447 files, no rewrites; only 30 protected formatter errors; `DenseReview-SummaryFullLint-20261022.log` |
| Rules | 230 findings / 98 rules; one fewer `ALL-FUNC0008` signal (74, previously 75); 87 Swift migration signals remain; `DenseReview-SummaryRules-20261022.log` |
| Exact Swift scope | `.build/Reports/DenseReview-SummarySource-20261022.sha256`; owner hashes and frozen V1 remain unchanged |
| Hosted prerequisite | `DenseReview-MainboardPin-20261022.log` still returns HTTP 422 for unpublished Mainboard `b34c931` |

The full declared phone gate contains 66 methods: 57 review methods and nine native-root
methods, with five review methods covered by separate URL-event lanes. Earlier 57-method
wording counted only the review class; these focused passes accept neither complete gate
nor final-source iPad/Mac interaction. Physical accessibility/IME/voice, signed services,
watch continuity, real-data calibration and storage acceptance remain tracked in TASKS.
No real account/exercise, microphone permission, signing, PR, push or distribution is used.
