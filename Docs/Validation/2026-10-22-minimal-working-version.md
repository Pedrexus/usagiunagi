# Minimal working version — October 22

Continuation of the [voice checkpoint](2026-10-22-voice-devices.md), after source changes
and current phone/iPad/Mac visual inspection. This accepts local fixture behavior, not a
signed release or physical-device microphone/iCloud acceptance. No real exercises were
submitted, and no credentials or account data were changed.

## Current-source evidence

Logs are retained in `.build/Results`.

- `MVP-SharedTests-20261022.log`: full shared Swift Testing suite exits zero; 542 test
  functions across four test executables (109 + 17 + 171 + 245).
- `MVP-PhoneUI-20261022.log`: eight of nine journeys pass: lessons and uploads, quiz
  mistake handling, typed reviews and uploads, draft restoration, token connection,
  settings/download navigation, inline coverage and cold routes. The lesson-picker return
  from quiz fails; its screenshot and event archive show the automation tap at the chip's
  pre-keyboard location (y810), while the visible chip is above the keyboard (about y508).
  `MVP-LessonNavigation-Geometry-20261022.log` passes the affected journey after waiting
  for the button's frame to clear the keyboard before its normal tap. All page, selection
  and draft assertions remain. Nine distinct phone journeys are accepted across these runs.
  The exact final source passes again in `MVP-LessonNavigation-Verified-20261022.log`.
- `MVP-MacColdRoutes-20261022.log`: the corrected cold-route/single-window check passes.
- `MVP-PersistenceReopen-Final-20261022.log`: separate writer and reader processes pass
  production SwiftData catalog, assignment, session, uncertain review, attempted note and
  account-isolation checks on disposable stores. This supplements UI fixtures, which use
  in-memory storage and cannot prove persistence across application relaunch.
- `MVP-ReleasePolicyIOS-20261022.log` and `MVP-ReleasePolicyMac-20261022.log`: both
  release-bundle audits succeed with no policy violations. Retired FMDB/PromiseKit/Haneke
  paths were not reintroduced; the configured policies specifically inspect retired
  database/library symbols, excluded fixtures, localized names and required metadata.
- `MVP-Lint-Commit-20261022.log`: 440 files checked, none rewritten, no failures.
  The broader rule inventory still has 211 advisory findings; it is not a clean-rule claim.
- Frozen V1 schema and all five historical writer/fixture checksums remain unchanged.

## Harness corrections and retained failures

The first persistence probe reaches and passes saved-session recovery, then exits because
its catalog writer fails to catch its deliberately injected timeout. The renewed probe
reaches catalog reading and exposes an obsolete expectation: `catalogRefreshID` is a
pending-refresh marker, consumed by a completed catalog refresh. A material upload does
not create it. The final probe catches only the expected timeout, requires the consumed
marker, and retains the catalog contents and uncertain-note assertions. Both failed logs
remain alongside the passing final log. No persistence runtime change was necessary.

The Mac cold-route test now checks the current app bundle identifier when confirming
termination, rather than an obsolete desktop identifier.

Lesson navigation's content-shape and safe-area layout experiments did not fix the failed
automated tap; both production experiments were reverted. Their failed receipts remain in
`MVP-LessonNavigation-Renewed-20261022.log` and `MVP-LessonNavigation-SafeArea-20261022.log`.
The accepted test uses a bounded geometry predicate, as the existing review-submit helper
does. It neither dismisses the keyboard nor bypasses the button action.
An alternate coordinate-tap trial also failed (`MVP-LessonNavigation-Final-20261022.log`)
and was discarded. Passing lesson picker/teaching/draft screenshots are retained under
`MVP-LessonAcceptedCaptures-20261022`; the restored draft was visually inspected.

## Remaining acceptance

- Paired physical Watch/phone delivery, live Japanese/English microphones, interruption
  handling, permission/model installation and background/locked-phone behavior.
- Signed private iCloud settings synchronization across devices and distribution signing.
- Broader original-app usability/accessibility comparison, statistics calibration and
  remaining advisory-rule cleanup. Local success does not close these tasks.
- Hosted GitHub Actions depends on the separately tracked unpublished Mainboard revision;
  this checkpoint does not publish dependencies, push a branch or create a PR.

## Statistics rendered follow-up

After `2ed3b434`, a current Mac screenshot exposed a blank future-schedule chart when all
seven days have zero additional reviews, plus vertically centered cards in the adaptive
grid. The shared dashboard now displays an empty-schedule explanation and aligns cards
at their top edges. Scheduled data still uses the existing chart; calculations are unchanged.

- `Statistics-MacAcceptance-20261022.log`: one pace comparison journey passes. The two
  other requested selectors belonged to `MacCatalogTests`, not `MacStatisticsTests`, so
  this receipt is counted as one test only.
- `Statistics-MacCoverageSchedule-20261022.log`: both correctly scoped coverage and
  schedule journeys pass, including filters, tab restoration, source disclosure and
  expanded stage/subject counts. No modal reopens.
- `Statistics-MacLayout-20261022.log`: the pace journey passes after the layout change.
  Its fresh screenshot in `Statistics-MacLayoutCaptures-20261022` was visually inspected
  against `Statistics-MacPaceCaptures-20261022`: the empty plot is gone, cards align,
  and the comparison chart, legend and explanation remain legible.
- `Statistics-IOSBuild-20261022.log` and `Statistics-Lint-20261022.log` exit zero.
  Lint checks 440 files without rewriting or failures.

These are isolated synthetic accounts. The pace implementation excludes future outcomes
from historical training, and the UI explicitly distinguishes kanji coverage from exam
readiness. This review does not provide full-account calibration, physical accessibility
acceptance, or an exam-success prediction. Older Mac automation timeouts in the task ledger
remain historical; these specific native journeys now run successfully.

## Accessibility follow-up

After `699953a6`, source inspection found two context-free button labels: repeated font
Download/Retry/Cancel actions and repeated lesson-group Select all/Clear actions. Their
spoken labels now include the font or level/type group; visible titles remain compact.

`Accessibility-Phone-20261022.log` passes largest-text Home actions/progress and lesson
heading/footer checks. Its review check fails while trying to inspect an English `a` key
on the selected Japanese keyboard. The helper now checks the keyboard's actual first key
using the same existence, nonempty-frame, containment and nonoverlap assertions.
`Accessibility-Phone-Renewed-20261022.log` passes both group-selection labels and the full
largest-text review journey: 250% question font, draft preservation through settings,
portrait/landscape geometry, continued typing, grading feedback, reveal and native
hit-region audit. The first failed receipt is retained.

Fresh captures live in `Accessibility-Captures-20261022`. The landscape draft and portrait
completion feedback were inspected. The landscape app capture does not display the
system keyboard; its keyboard geometry assertions must not be treated as a screenshot
of that keyboard or as physical keyboard/VoiceOver acceptance. The portrait capture does
show Japanese input beneath the answer and tools.

`Accessibility-MacBuild-20261022.log` and `Accessibility-Lint-20261022.log` exit zero.
`Accessibility-FontActions-20261022.log` passes the actual download/cancel/retry/deletion
cancellation journey and exact contextual accessibility labels, using isolated font fixtures.
These checks do not close full VoiceOver, Reduce Motion, contrast or physical-device gates.

## Shared app and iPad follow-up

`Adaptive-iPadCore-20261022.log` passes three native iPad Pro 11-inch (M5), iPadOS 27
journeys: lesson teaching/quiz with automatic upload, typed reviews with automatic upload,
and contextual group selection/clear. These use the same production views and isolated
fixture transports as iPhone; they submit no real WaniKani exercises. This supplements
the earlier six iPad voice journeys, rather than substituting for them.

The current-source search across `Shared/Sources`, `App/Application` and `App/Watch`
finds one view representable (`StudyAnswerInput`) and no controller representable.
The [boundary inventory](../Implementation/2026-10-22-legacy-removal.md#current-platform-boundaries)
records remaining UIKit/AppKit and native service uses, their concrete owners and the
behavior required before replacement. Two obsolete legacy-host comments are corrected;
no runtime, persisted field, bridge or feature is deleted in this audit.

`Adaptive-BoundaryLint-20261022.log` exits zero. Physical IME, paired Watch, signed iCloud,
and broad window-resizing/keyboard/accessibility acceptance remain open.

## Full hosted regression and test-selection safeguard

`Regression-HostedIOS-20261022.log` passes 85 test functions (154 parameterized
executions), with one deliberate separate-process restart skip. The corresponding
Mac log passes 67 functions (134 executions), with the same skip. Neither suite
reports runtime warnings. These are isolated fixtures, not physical-device acceptance.

Mainboard commit `fa467e0` now rejects a native passing result when an explicitly
selected exact test method is absent. It preserves Xcode's summary and reports
`missing_selectors`, accounting for skipped cases, explicit exclusions and parameter
labels. All 85 Apple integration checks pass; the isolated package type check reports
zero diagnostics with its two existing suppressions. Initial failing trials remain
in Mainboard's `build/apple-selectors-20261022` and temporary type-check receipts.

The remote lookup for the workflow's `b34c931` pin still returns HTTP 422. The published
remote revision lacks the required Apple tooling, so substituting it would break the
workflow. No tooling or app commits were pushed; hosted CI remains unverified.

## Further dead-code audit

Removed the unused duplicate `Tsurukame Complication (Complication)` scheme. Its build
references duplicated the maintained Watch scheme; the only execution distinction was
an old complication launch substyle. The current Watch app and WidgetKit extension,
maintained Watch scheme and CI references remain intact.

The declaration/reference scan found no orphaned UI or persistence functions beyond
framework entry points and protocol callbacks. Frozen receipt fields that appear only
in declarations are Codable storage contracts, not dead settings; they remain intact.

The Core audit also removes `UploadCoordinator.swift` (82 lines) and its isolated
`UploadCoordinatorTests.swift` (128 lines). All four obsolete types were referenced only
inside those two files. Production uploads already run through `StudyStore.uploadPending`,
with durable SwiftData acknowledgements and account/run cancellation guards. Its active
persistence regression suites remain. The removed test count must not be presented as
lost coverage of the current upload path.

`Cleanup-WatchBuild-20261022.log` passes after the scheme removal with zero compiler or
analyzer warnings. This precedes the dead coordinator removal; final shared verification
is recorded separately below.

Final `Cleanup-SharedTests-20261022.log` passes all remaining shared suites after
removal. `Cleanup-Lint-20261022.log` checks 437 files, rewrites none and reports no
failures. The frozen V1 schema retains SHA256
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`;
all five frozen writer/baseline checksums verify. This cleanup deletes 304 code/config/
test lines and does not remove any active UI, grading or upload path.

## iPhone review parity completion

On app commit `e7a606ca`, `Review-ParityCompletion-20261022.log` passes three native
UI journeys on iPhone 18 Pro / iOS 27 with no skips, failures, or compiler warnings:

- Previous-subject navigation shows the completed subject, preserves the current draft,
  and accepts more typing on return without a field tap or question/progress change.
- Combined Anki exposes the correction actions; dismissing that menu awards no credit.
  An incorrect assessment requires another reveal/assessment before completion.
- Wrap-up can be enabled, stopped, resumed, and completed with the reading answer.

Exact bundle: `test-a04b76070ee143d99b9189f21acf7a58.xcresult`. All three requested
method identifiers are present in its result tree. These isolated fixtures submit no
real WaniKani exercises. They close the previously unexecuted iPhone scenarios, not
physical keyboard/IME, full original-flow parity, or paired Watch acceptance.

## Release verification after final cleanup

Against `09321cfc` (the current runtime sources from `e7a606ca`), both
`FinalCleanup-ReleaseIOS-20261022.log` and `FinalCleanup-ReleaseMac-20261022.log`
exit zero with no compiler or analyzer warnings. These are unsigned iPhone simulator
and native Mac Release products, not device-signed archives.

`FinalCleanup-BundleIOS-20261022.log` and `FinalCleanup-BundleMac-20261022.log`
both report `successful: true` and no violations. The declared policies verify localized
English/Japanese/Simplified and Traditional Chinese display names, icon metadata,
microphone usage descriptions, excluded test/store fixtures and retired library symbols.
No policy was weakened and no signing, push, hosted CI or distribution was performed.

The preceding three-journey iPhone receipt includes `missing_selectors: []`: the local
Mainboard `fa467e0` safeguard is active. Compact console output omits the empty list;
the durable JSON contains it. No environment replacement was needed.

## Home study-action contrast

Native contrast inspection found the small Available now heading too faint in light mode.
Using hierarchical `.primary` retained the inherited section gray; explicit `Color.primary`
corrects it. Available now and Upcoming reviews now use that adaptive semantic color.
The WaniKani card colors, typography and layout are unchanged.

- `Accessibility-HomeContrast-20261022.log` and `...-Fixed-20261022.log` retain the
  original heading failure and ineffective hierarchical-style attempt.
- `Accessibility-HomeContrast-Semantic-20261022.log` clears that heading and then reports
  Next level-up review beneath the translucent tab bar. That broader finding remains open.
- `Accessibility-HomeStudyContrast-20261022.log` and `...-Final-20261022.log` pass the
  explicitly scoped native audit for both study buttons and both headings in light/dark
  appearances. Other findings are retained as attachments rather than counted as passing.
- `Accessibility-HomeStudyContrast-Negative-20261022.log` restores the old heading color
  temporarily and fails specifically on `home.availableHeading`; the source is restored
  automatically. This proves the scoped issue handler does not ignore the original bug.
- `Accessibility-HomeStudyContrast-FormattedLint-20261022.log` checks 437 files and passes.
  The only edit after the final native run is formatter line wrapping in the new test.

Final captures are in `Accessibility-HomeStudyContrast-FinalCaptures-20261022`. The light
post-audit and dark pre-audit captures show both readable headings and complete study cards.
Some other captures around native contrast auditing omit the white card content; those
captures are retained, not treated as complete visual acceptance. Further capture/rendering
investigation and the separate tab-bar overlap finding remain open.

The Reduce Motion source audit leaves the existing suppression unchanged. Apple's
[symbolEffectsRemoved documentation](https://developer.apple.com/documentation/swiftui/view/symboleffectsremoved(_:))
describes inherited effects; the current modifier sits inside the bounce modifier. This is
source/documentation evidence, not executed Reduce Motion acceptance. The installed simctl
UI controls expose appearance, contrast and content size, but no Reduce Motion switch.
Physical VoiceOver and a genuinely enabled Reduce Motion run remain required.

## Timing-row viewport and device prerequisites

`Accessibility-HomeTimingContrast-Viewport-20261022.log` passes the timing-label
contrast audit in both light and dark appearances after a normal upward swipe. Frame
assertions require the complete label between the navigation bar and tab bar. This
shows the earlier initial-viewport issue does not persist when the row is scrolled into
its reading position; it does not accept content legibility beneath glass.

The initial `Accessibility-HomeTimingContrast-20261022.log` fails before auditing because
the generic scroll helper requires a static label to be hittable. The renewed test uses
normal scrolling and reading-frame assertions instead. Broader native findings remain
attached: in light mode, Recent mistakes/Extra study/Current level headings and explanatory
text; lower level controls also appear in both modes. Their visibility and contrast need
individual inspection before dismissal or correction. The new test only accepts the timing
label and explicitly retains all other issues.

A fresh `devicectl list devices` shows the physical iPhone 16 Pro Max unavailable; all
connected iPhone/iPad/Watch entries are simulators. The owner has been asked to connect
and unlock the paired phone and identify the intended Apple Developer team. No device
installation, signing changes, normal-account launch or iCloud write was attempted.
The project still has the original phone team ID and no Mac team. These prerequisites
remain pending while independent local work continues.

## Broader visible Home contrast

The light-mode Recent mistakes/Extra study/current-level headings and explanatory text
now use explicit adaptive primary text. The broader audit then identified dark-mode
Radicals text as insufficiently contrasted. Subject names now use primary text while
icons and progress bars retain the WaniKani blue/pink/purple palette.

The two narrow tests are consolidated into `testHomeContentContrastAcrossAppearances`.
It audits every reported element fully inside the content rectangle between navigation
and tab bars, at the initial position and after scrolling to forecast/level progress.
Unknown or empty-frame findings fail rather than being discarded. Findings outside the
unobscured viewport are retained with their exact frame and viewport; there is no label
whitelist. The timing row must be fully clear of both bars.

`Accessibility-HomeVisibleContrast-20261022.log` retains the real dark-mode Radicals
failure. `Accessibility-HomeVisibleContrast-Labels-20261022.log` passes the same expanded
audit after the text fix, with zero skips. Its bundle is
`test-9cda9ebc7e8f4c4f9d8709141a36f763.xcresult`.
`Accessibility-HomeVisibleContrast-Lint-20261022.log` passes all 437 configured files.

Both scrolled light/dark captures in `Accessibility-HomeVisibleContrast-Captures-20261022`
were inspected: headings, explanations and subject names remain legible; colored icons
and bars, compact rows and native glass navigation remain. This accepts these two Home
viewports, not the lower Home sections, every page, glass-obscured content, Reduce Motion,
or physical VoiceOver. No account data or grading/storage code changed.

### Complete Home contrast sweep

Extended the existing contrast audit through the final community link in both light and dark
appearances. Lower section headings, counts, empty-state text and the community label use
adaptive primary text. Final lower-page captures were visually inspected. The native test
passes (one test, no skips or failures) in `test-defa1130a1184c7f9b884bc332cecd3e.xcresult`;
`Accessibility-HomeFullContrast-Final-20261022.log` and
`Accessibility-HomeFullContrast-FinalLint-20261022.log` retain the results (437 files, no failures).

The audit records exceptions for content outside the unobscured viewport and text contained
in runtime-verified disabled buttons (Master and Enlightened with zero items). Unknown issue
frames still fail. This follows the inactive-control exception in the W3C contrast-minimum
criteria; it is not a claim of full accessibility conformance. Intermediate contrast failures
and a native audit timeout remain in the local logs. Scope is the normal-size synthetic Home
fixture; other pages, VoiceOver, Reduce Motion and physical-device acceptance remain open.

### iPhone foreground reopening

Extended the existing romaji/draft/settings/pause journey with two real Home-button background
transitions and app activation. The test requires the app to reach the background state,
preserves the unsubmitted `いち` reading on return, and preserves an open review-settings sheet
through a second background transition. Closing settings and pausing/resuming still retain the
draft. This uses injected memory-only fixture services, with no real account or exercises.

Current native execution passes one test with no skips/failures in
`test-c19628ebe97b45809ccd93c0d38b2dcc.xcresult`, retained in
`ReviewReopen-20261022.log`. Build summaries report no compiler/analyzer warnings; the separate
AppIntents metadata extraction notice remains. Mainboard lint passes in
`ReviewReopen-Lint-20261022.log`. This is foreground lifecycle evidence on iPhone 18 Pro/iOS 27
Simulator, not process-death restoration, Mac window reopening or physical-device acceptance.

### Mac foreground and cold-link reopening

Extended the existing typed-review journey with Command-H, a required background-state
transition, reactivation and a single study-window assertion. The unsubmitted draft and
question survive; pause/resume still preserves them, submitting clears the field, and the
fixture review completes. Cold subject/review/lesson links each launch one window. Their
precondition now waits for the tested application to stop instead of querying the old iPhone
bundle identifier, which did not establish the Mac process state.

The first run (`MacReopen-20261022.log`) retains a failure caused by an outdated bare
Meaning/Reading test expectation. The UI includes the subject type; the corrected test
checks the question suffix, preserves the full prompt for equality across reopening and
unwraps the value explicitly. No production behavior changed.

Both native tests pass, without skips/failures, in
`test-3238eb2cef624938a933d1af4e9a734e.xcresult` and
`MacReopen-Final-20261022.log`. Compiler/analyzer summaries report zero warnings.
`MacReopen-FinalLint-20261022.log` passes 436 files without rewrites. These are isolated
fixture-account journeys. Cold links deliberately ignore saved window state; they do not
prove real-account window restoration after termination or physical iCloud/Watch behavior.

### Mac lesson, draft and exclusion parity

Updated remaining bare Reading comparisons to account for subject-qualified prompts. Lesson
pause now takes the actual Choose lessons action before returning Home. Exclusion checks use
the current saved-summary title and explicitly require `0/0` credit. Mac Anki exposes a native
split PopUpButton, so the helper opens its nested menu button; typed correction uses its
ordinary menu. No production source changed.

Eight distinct fixture journeys have passing results across retained runs (not one all-green
combined suite):

- `MacStudyParity-20261022.log`, `test-7353b1646375418f9d4ff679e73a8fb2.xcresult`:
  discard, extra study without scheduled-review changes, retry draft and wrap-up pass; lesson
  navigation and the stale exclusion summary expectation fail in that initial run.
- `MacStudyParity-Final-20261022.log`, `test-cc76e381f14b4160adff6c20533f21b5.xcresult`:
  corrected lesson teaching/quiz/pause/resume/completion and typed exclusion pass; Anki
  selectors fail. Those suite failures remain recorded.
- `MacStudyParity-AnkiMenu-20261022.log`, `test-9c297c9e34e84af6962777a4e83454f9.xcresult`:
  Anki lesson and review exclusion pass, no skips/failures, with zero completed-answer credit.
  Native compiler/analyzer summaries report no warnings.
- `MacStudyParity-MenuLint-20261022.log`: 436 files, no rewrites or failures.

Intermediate `Anki` and `AnkiSplit` logs retain failed selector/dialog trials. The latter reveals
an unresolved UI difference: the Mac primary assessment confirmation dialog shows only correct,
incorrect and ask-later actions, whereas exclusion is available through the split-button menu.
Do not infer dialog feature parity from the passing menu tests. Investigate the conditional
advanced actions and native dialog rendering before closing that UI requirement. The review
and lesson grading/outbox paths remain unchanged; all execution uses isolated fixtures.

### Adaptive assessment repair

Replaced the assessment-only confirmation dialog with one SwiftUI popover attached to the
assessment control. It uses the existing shared action body, adapts to a sheet in compact
layouts and dismisses before forwarding an action. There is no new platform conditional,
framework or grading path. Cancel remains an explicit no-credit exit; exclusion and synonym
editing are available alongside correct, incorrect and ask-later actions.

The original native Mac dialog omitted advanced actions even when its construction received
both capability flags as true. Explicit presentation data and a data-driven action-list trial
did not fix the rendered omission; both were removed. Temporary boolean-only diagnostics
were also removed. The exact framework cause is unproven; no undocumented action limit is
assumed. Apple's [confirmation-dialog contract](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:))
does not describe this omission. The retained presentation follows Apple's
[popover guidance](https://developer.apple.com/design/human-interface-guidelines/popovers)
for a few related tasks, with automatic compact adaptation and a control-relative anchor.

Current evidence:

- Mac `AdaptiveAssessment-MacComplete-20261022.log`,
  `test-8ed822c6074c4bd9903126aed80d0e61.xcresult`: all five actions visible, cancel returns
  without assessment, synonym alert opens after dismissal, canceling it permits reassessment,
  and exclusion finishes with `0/0` credit. One test passes without skips/failures.
- iPhone `AdaptiveAssessment-iPhone-20261022.log`,
  `test-fd05d4ae16ec4ed9952287bdeb32894d.xcresult`: existing combined-Anki cancellation,
  incorrect assessment and eventual correct completion passes without skips/failures.
- iPad `AdaptiveAssessment-iPad-20261022.log`,
  `test-bdab793419f7453588cec8c06c8f6f3d.xcresult`: the same flow passes in the wider presentation.
- `AdaptiveAssessment-FinalLint-20261022.log`: 436 files, no rewrites/failures.
- The earlier `AdaptiveAssessment-MacVerified` run also passes the separate native menu path.
  The captured Mac assessment was visually inspected: all actions fit and the arrow points to
  the assessment control. The capture comes from `MacFinal`, whose later test failure was an
  ambiguous Cancel query matching both the alert and Touch Bar; the final test scopes that query.

Prior failed dialog trials (`MacAssessmentData`, `MacAssessmentCapabilities`,
`MacAssessmentActions`, `MacAssessmentActionList`, `AdaptiveAssessment-Mac`, `MacFinal`)
remain in ignored results. The first `AdaptiveAssessment-Mac` compile failure came from an
incomplete edit, not a runtime regression. Final source contains no diagnostic print or
experimental action metadata. This closes the observed advanced-action presentation issue;
physical VoiceOver, larger-text presentation and broader app acceptance remain separate.

### Assessment at largest Dynamic Type

A new native iPhone journey exposed clipped assessment text and an unreachable Cancel action
at Accessibility XXXL. The fixed medium-height, non-scrolling view could not recover the last
action. The shared presentation now scrolls, gives action labels their intrinsic vertical size,
uses native borderless buttons with minimum 44-point height, and allows medium/large sheet
heights. Ideal popover dimensions guide layout without fixing its size. No platform branch
or grading change is added.

`AssessmentLargeText-Scrolled-20261022.log` and
`test-fd8c2b7d6cf04b4881698e1a28dbc9dc.xcresult` retain the actual Cancel failure and before
capture. An earlier `AssessmentLargeText` run failed before review entry because the lazy Home
list had not loaded the button; the final test explicitly scrolls Home as a user would.

`AssessmentLargeText-Final-20261022.log`,
`test-c0d3b079d0274174be85451a244f595c.xcresult`: two tests pass without skips/failures. Every
assessment action becomes hittable and fully inside the window at the largest category;
Cancel preserves the question/progress. The ordinary combined-Anki incorrect/correct flow
also passes. Opening and final-action screenshots were inspected: full labels wrap, the sheet
expands, and Cancel is visible. Captures live in `AssessmentLargeText-After-20261022`.

`AssessmentScroll-Mac-20261022.log`,
`test-7c31a34cac7b4bd194ed62f40eafe3a6.xcresult`: the Mac action/cancel/synonym/exclusion
regression passes with the scrolling view and zero exclusion credit. Mainboard lint passes
436 files in `AssessmentLargeText-Lint-20261022.log`. These scoped runs do not establish
physical VoiceOver, every window dimension or all app-wide accessibility requirements.

## Pending-review coverage correction

Offline review subjects were intentionally withheld from statistics assignments, but coverage
interpreted that absence as “Not started.” The current projection carries transient outbox subject
IDs, populated by both snapshot reads and refresh. Coverage partitions those kanji as “Awaiting
sync”; the SRS chart discloses withheld items. Assignment exclusion and server-authoritative grading
remain unchanged. The new IDs are omitted from the existing CodingKeys and default empty when
reading stored snapshots; they are reconstructed from the outbox, not persisted.

`PendingCoverage-Shared-Final-20261022.log` passes all 540 shared test functions
(109 + 17 + 171 + 243). Added checks cover pending/unstarted/outside-catalog partitioning, normal
coverage after sync, and byte-identical encoded snapshots with/without transient IDs. Existing
reopen and refresh tests now also assert those IDs match the outbox. The initial shared attempt
failed to compile a new assertion referring to a nonexistent question.subjectID; the corrected
assertion reads the outbox. It was a test-authoring error, not an app runtime failure.
`PendingCoverage-Lint-20261022.log`: 436 files, zero rewrites/failures. Frozen schema source SHA256
remains 538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4;
all five frozen-fixture checksums pass. These checks do not replace historical on-disk schema
reopening or a rendered UI acceptance check for the new legend, which remain to be run.

The full iPhone acceptance lane started from 9cfb5ead before this source change, and remains
running in session 17816 (`FullPhoneAcceptance-20261022.log`). Its receipt will apply to those
already-built products, not to the pending-coverage correction. No second UI suite was launched.

### Pending coverage: historical storage acceptance

At commit `60d2ab59`, `PendingCoverage-FrozenStore-20261022.log` passes the current
`read-native-baseline` probe: disposable copies restore exact baseline fields, revisions,
ownership and schema twice. `PendingCoverage-SchemaUpgrade-20261022.log` also passes:
38 exact records across 10 models, fresh-process named V1 comparisons, real saved transaction
reopening, and a 49,472-byte WAL-only commit copied with exact durable fields. Original frozen
fixture names and SHA-256 hashes remain unchanged. Writable source SHM bookkeeping changes
are explicitly reported; protected source generations remain unchanged. These are scoped Mac
storage checks, not iOS fault-matrix, power-loss or physical-device proof. The historical reopening
item above is now satisfied for this correction; rendered coverage acceptance remains open.

The pre-correction full iPhone lane continues in session 17816. Reduce Motion acceptance is
explicitly skipped because the simulator system preference is not enabled; that requirement is
still open rather than counted as a pass. No final full-suite result exists yet.

### Pending coverage visual check prepared

Each curriculum target now also shows its nonzero awaiting-sync count as text. This makes a single
pending kanji visible without relying on its very small bar segment. The new iPhone native-root
regression reuses `--review-recovery-fixture`, checks N5 reports one awaiting sync with zero of 79
confirmed, expands all 79 remaining kanji, and retains a screenshot. It does not answer a review.
`PendingCoverage-Visual-Lint-20261022.log` passes 436 files with no rewrites/failures. The new UI
regression is pending execution after the existing suite finishes; no visual pass is claimed.

### Pending coverage rendered iPad acceptance

`PendingCoverage-iPad-20261022.log`, bundle `test-757d8e89f3fc42dfa01d0eef433ba9b0`,
passes the new pending-coverage regression on the independent iPad M5 simulator (one test,
no skips). The retained screenshot was inspected: all five legend labels fit, the pending
segment is separate, N5 states “1 awaiting sync” and zero confirmed of 79, and expansion
shows the remaining kanji inline without a modal. Screenshot:
`.build/Results/PendingCoverage-iPad-Captures-20261022/B7737AB8-CC3C-4367-B7B8-C75E98A65921.png`.
This used separate iPad derived data and device while the original iPhone suite continued;
it does not replace iPhone compact rendering verification.

### Developer endpoint editor regression and repair

The ongoing full iPhone suite at `9cfb5ead` reports a failure: Cancel leaves the API URL alert
visible. A five-second dismissal wait reproduces the same failure on iPad after fixing an
independent test helper issue: Settings is a floating form there, and the helper had been
scrolling disabled Home behind it. It now scrolls the enabled foreground collection.

Explicit alert-state dismissal and moving the alert to the initiating button both fail; those
trial implementations are removed. The final URL editor is a native SwiftUI form sheet with
Cancel/Save toolbar actions and a Reset row, retaining URL normalization and parent error
reporting. The complete existing iPad edit/cancel/invalid/save/reopen/reset journey passes:
`DeveloperEndpoint-iPad-Sheet-20261022.log`, bundle `test-e82c7d1a355d4abab83ef21fcf43bf7f`.
Failed trial logs remain `DeveloperEndpoint-iPad`, `-Foreground`, `-Dismiss`, and `-Scoped`.
No unproven framework-level cause is asserted.

`DeveloperEndpoint-FinalLint-20261022.log`: 436 files, no rewrites/failures.
`DeveloperEndpoint-MacBuild-20261022.log`, bundle `build-c9141653b7d94f4d8b1cfe76bf489a7b`:
native Mac build succeeds with zero compiler/analyzer warnings. The iPhone full run is still
active in session 17816, testing its original products, so its endpoint failure cannot verify
this repair. A focused iPhone endpoint and pending-coverage rerun is required after it ends.

### Audio acceptance and local cache cleanup

`OfflineAudio-iPad-20261022.log`, bundle `test-7125445fe296445e9113e0517f7a83df`,
passes all three native offline-audio journeys: download/Keep/explicit deletion, visible failures
and retry, and persistent voice/cellular choices. No audio production code changed. The full
pre-fix iPhone run has an unresolved download-test enable-toggle assertion failure; the other
two audio tests pass there. A focused iPhone rerun remains required before classifying that
failure or claiming complete audio acceptance.

Removed seven ignored, unused generated build directories after checking current task/workflow
references and live xcodebuild processes: LegacyPackageReconcile, NativeCanonicalMac,
NativeCatalogsMac, NativePackageReconcile, ProtobufPackageUpgrade, ProtobufPluginUpgrade and
SubjectsShared. Their reported total was approximately 2.6 GiB. Current iOS/iPad/UnifiedMac/
Watch directories, validation reports and frozen source/data fixtures remain. No tracked
source or shared/global cache was removed by this operation.

### Full iPhone lane: bounded completion and focused recovery

The original `9cfb5ead` run ended with exit 124 at its 1,800-second bound. Its log records
57 passing methods, three failures (endpoint Cancel, audio-enable assertion, lesson drag
assertion), one explicit Reduce Motion skip and an interrupted Settings review test. The
`test-12876e94c212457db684e965d0e44360.xcresult` directory lacks a finalized root/Info.plist;
it is not a complete result bundle. Keep the log and interrupted directory as failure evidence.
The Actions iOS matrix now allows 2,400 seconds for this lane and 60 minutes for the job,
including separate event-driven lanes. Bounds remain finite; no hosted run is claimed.

`PhoneRemainingAcceptance-20261022.log`, bundle `test-3906a5d0c9ee4b7da207033c028f43c1`,
completed all 11 selected methods: nine passed, two failed. Audio download/Keep/deletion and
lesson order passed without production changes to either feature. Remaining Settings, cold
links, notification persistence, forecast, voice transcript and wrap-up cases passed. Its two
failures were the endpoint test leaving `/v2` after typing at a mid-field caret and the summary
test expecting the old “Missed · level 1” heading instead of “Missed · current level (1)”.

The endpoint helper now invokes the visible Select All editing action before replacement,
retaining exact text and dismissal assertions. Hardware Command-A and triple-tap trials did
not reliably select all URL text and are not retained. The summary assertion uses the current
heading while retaining missed-meaning/reading, subject-detail and return checks.
`EndpointSummary-iPhone-20261022.log`, bundle `test-79efe98b7e5f42e184dc56fb2ebac550`,
passes both complete journeys, no skips. Across the original log plus completed focused
bundles there are 68 distinct logged passing iPhone methods; this is not a single clean full
suite. Reduce Motion and five separately event-driven selectors retain their distinct scopes.

The pending-coverage iPhone screenshot from the 11-method bundle was inspected:
`.build/Results/PhoneRemaining-Captures-20261022/172A5885-0B18-44D9-9FE9-53A6C29B2463.png`.
The five-part legend wraps onto two lines without clipping; N5 has the correct pending count
and expands inline. Its lower content extends below the floating tab bar and requires scrolling;
this screenshot does not claim an all-visible expanded grid or largest-text acceptance.

Independent iPad lesson ordering also passes: `LessonReorder-iPad-20261022.log`, bundle
`test-017f8a5ad4944bafaa1adf454f972eac`. Current code follows Apple's documented ForEach
`.reorderable()` plus container `.reorderContainer` pattern:
https://developer.apple.com/documentation/swiftui/reordering-items-in-lists-stacks-grids-and-custom-layouts
No drag implementation was changed solely to satisfy a failed test.

`PhoneAcceptance-FinalLint-20261022.log`: 436 files, no rewrites/failures. The iPad two-method
endpoint/summary run is still active in session 79517 with a 600-second bound; endpoint passed
but summary has long automation-idle waits. Do not count its entire run as accepted or restart
it while its handle is live.

### iPad endpoint/summary follow-up

`EndpointSummary-iPad-20261022.log` records the endpoint editing flow passing in 53.959 s.
The summary journey encountered repeated accessibility-server and animation-idle waits;
the bounded run exited 124 at 600 seconds. The bundle
`test-27425c45959047ffbc95b441753d70de.xcresult` lacks Info.plist and is incomplete.
This is not a completed passing suite. The read-only live screenshot
`iPad-Summary-Idle-20261022.png` confirms review feedback rendering only. The completed
iPhone endpoint/summary receipt remains valid for its own platform and source scope.

### iPhone final selector publication ENOSPC

The fixture-only opening-pressure extension passes both its focused four-host run and the
integrated seven-host Mainboard storage matrix, without skips or failures. Final publication
fails with Cocoa/640 at the exact selector URL; a fresh retry preserves all 38 baseline records,
uses a different candidate, and saves a pending note that survives two further process reopens.
The existing note/review/WAL save cases still pass. Both temporary APFS images were ejected
and removed. Mainboard lint passes all 436 files; production V1 and frozen fixture hashes
are unchanged. [Exact protocols and bundles](../Implementation/2026-10-21-frozen-ios-and-review-focus.md#iphone-final-selection-publication-disk-full).
Earlier capture/verification, committed-WAL opening and physical failure gates remain open.

### iPad review-summary recovery after simulator restart

The previously stalled process identified in the AX log was the simulator's `druid`
(DragUI service), not the app. Restarted only the iPad simulator without erasing data.
The unchanged summary test then passed in 29.772 s; no assertions, waits, app code or
animation settings were changed. The service's AX warning still appears in the successful
run, so that warning alone does not establish the cause of the earlier timeout.

`Summary-iPad-Reboot-20261022.log` and
`test-8579a73a2f9c45b9b3480eadfe170efa.xcresult`: one pass, no skips/failures,
zero compiler/analyzer warnings/errors. The test completes a deliberately missed meaning,
verifies no reading miss, opens subject details, returns and finishes at Home.
The exported screenshot
`Summary-iPad-Reboot-Captures-20261022/01CAB140-38A1-4988-958B-FB2A7F3BAE97.png`
was visually inspected: saved-state explanation, 0%/0-of-1 subject accuracy, current-level
missed heading, 一つ/ひとつ and Meaning missed are visible without clipping; native Back
and Done remain accessible. This is portrait/default-text/light appearance, not broad
adaptive or accessibility acceptance. The earlier timed-out bundle remains retained.

The original two-test sequence also completes after the restart on source `2f8b5102`:
`EndpointSummary-iPad-Reboot-20261022.log`, bundle
`test-5f9082edd67e420ba760f5016e8a55ca.xcresult`. API endpoint Cancel/validation/persistence/
reset passes in 54.149 s; missed-subject summary/details/finish passes in 27.841 s.
Two passes, no skips/failures; zero compiler/analyzer warnings/errors. This closes the
specific iPad endpoint/summary acceptance gap. No production change or test relaxation
was necessary. Simulator restart recovery is evidence about this run, not proof of the
precise cause or a guarantee against future simulator stalls.

### Accessibility-sized review assessment on iPad and iPhone

The unchanged largest-text assessment test exposed a real iPad presentation problem:
the narrow popover displayed only about one and a half actions, while XCTest could not
scroll the assessment container. The retained failed bundle is
`test-588c232afc1e43d79211f56aedfd280b.xcresult`; its opening capture is
`Assessment-LargestText-iPad-Captures-20261022/174C5F2C-851F-412D-823C-B48C83322A40.png`.

`ReviewScreen` now selects a native sheet at accessibility Dynamic Type sizes and retains
the popover at standard sizes. One shared menu and action body supply both presentations.
This uses a text-size signal, adds no OS/device branch, and changes no grading or action
semantics. Accessibility-sized sheets request the large detent; the OS adapts them to a
centered sheet on iPad. Existing actions and Cancel are preserved.

The original reachability test passes unchanged on both simulators, asserting every action
is hittable and on screen, then cancelling without changing the question or progress:

- iPad: `test-6be7568d84bd46b2b1221bbc5e1186ba.xcresult`, one pass, no skips/failures.
- iPhone: `test-3e71a250fa664c328262d7d552f2f386.xcresult`, one pass, no skips/failures.
- Mac normal-size assessment/Cancel/synonym handoff: `test-adcc28295f9a4ed582db523462e73431.xcresult`,
  one pass, no skips/failures.

All three build summaries have zero warnings/errors/analyzer warnings. Mainboard lint passes
436 files. Fixed final-action captures were visually inspected:
`Assessment-LargestText-iPad-Sheet-Captures-20261022/9DC5DF37-A45A-4E31-8042-D98F43DE5C82.png`
and `Assessment-LargestText-iPhone-Sheet-Captures-20261022/1E7E6E9A-E7AC-4688-8E22-716FEA1E755D.png`.
Both show all six action labels, including Cancel, without truncation. This proves the
portrait/light/max-text assessment case, not all screens, landscape or VoiceOver behavior.

The installed simulator `ui` command supports appearance, contrast and content size but
not Reduce Motion. The existing Reduce Motion gate still requires the actual system
preference and remains open; this run does not substitute a view override for that gate.

### iPad adaptive Home and review follow-up

At source `e689e9a5`, `AdaptiveLayout-iPad-20261022.log` and bundle
`test-2d5b83dd4cdd4dc1bbcdab0352289399.xcresult` complete all three selected cases:
maximum-text Home action/progress navigation, Home counts/charts/refresh across rotation,
and landscape review with settings/draft preservation and completion. Three passes, no
skips/failures; zero build warnings/errors. The maximum-text progress screenshot was
inspected: wrapped explanatory text and current-level rows remain readable and navigable.

The landscape screenshot was captured during keyboard return after Settings. Its test had
checked keyboard/content visibility before opening Settings, but not again before capture.
The current test adds the same existing visibility predicate after dismissal; no fixed delay
or weaker assertion. That final capture/result is recorded separately below.

### Statistics local-clock correction

The dashboard previously cached `snapshot.metrics()` at initialization without a time-driven
parent update. Leaving Stats open could retain an old due count, calendar-day buckets and
elapsed pace scenario. The shared root now supplies `TimelineView(.everyMinute)` dates to
the existing metrics initializer. No new service, persistence type or network request is added.
The displayed saved-snapshot timestamp remains distinct from the live calculation date.

A fixture assignment is due 30 seconds after launch. The initial native iPhone run verifies
that it becomes due without leaving Stats and keeps Coverage inline:
`test-bca71f1ebaf446efa66adfbac8dd9ac6.xcresult`, two passes, no skips/failures. The final
version additionally asserts the displayed snapshot timestamp is unchanged.
Native Mac statistics tests pass all 11 cases, including deterministic Tokyo-midnight
rollover with identical assignments:
`test-566afa8be19d45a6a0e18e0ba9e10453.xcresult`. Zero build warnings/errors.
The preceding Mac invocation used the UI-only scheme and exited 70 before running tests;
`Statistics-Clock-Mac-20261022.log` is retained and not counted as evidence. The corrected
run uses the repository's `Tsurukame` hosted-unit-test scheme.

Final clock UI test: `Statistics-Clock-iPhone-Final-20261022.log`,
`test-c652b610221e4045baf4525a4bb4ca11.xcresult`, one pass with no skips/failures.
The due count advances from 0 to 1 while the displayed snapshot timestamp and selected
Progress section remain unchanged; no refresh gesture or re-navigation occurs.
`Statistics-Clock-FinalLint-20261022.log` passes all 436 files with no rewrites/failures.
This is fixture/time-driven acceptance, not new evidence of real-account forecast calibration.

Final iPad landscape check: `Landscape-iPad-Settled-20261022.log`,
`test-31840421a305480fa59e682386b051f8.xcresult`, one pass without skips/failures and zero
build warnings/errors. The post-settings visibility predicate now confirms question, prompt,
input, submit action, controls and keyboard geometry before capture. The exported
`Landscape-iPad-Settled-Captures-20261022/2A9A2211-EF7F-45E0-A244-9F7E379706EB.png`
was inspected: side-by-side subject/input remain above the fully presented keyboard,
with the preserved draft and review tools visible. The fixture then completes normally.

### Expanded iPhone opening disk-full matrix

`OpeningSpace-FullMatrix-iPhone-20261022.log` exits successfully. Mainboard report
`StorageSpace.NKZTwA` contains all seven passing process phases, with no skips/failures:

| Phase | Result bundle |
| --- | --- |
| save matrix | `test-6846a120c4cf4e3ab3410e95ff14315e.xcresult` |
| saved-state reopen | `test-2a277fc177194936a6395760a34d4dbc.xcresult` |
| saved-state verification | `test-ba7cfd418f8041ac8e8175717c7f793b.xcresult` |
| opening refusal | `test-181fa39fbf9b4970b8d074cca5b97c40.xcresult` |
| opening retry | `test-aa23b74ecaf7422f8eee2b21edb566bd.xcresult` |
| opening reopen | `test-b8679fca01fa4d5bb929c24c0f6b9561.xcresult` |
| opening verification | `test-d899d60f59d84ba69b0335132b1658a7.xcresult` |

The existing four opening phases now each cover verification attachment and final
selection publication with both journal-free and real committed-WAL sources. Each case
fills only the bounded APFS image, requires a genuine out-of-space error, preserves exact
source/retained/abandoned artifacts, retries with a different candidate, writes the exact
pending note and verifies it through two further process reopens. Mainboard checks all
seven receipts, positive pressure-byte counts, four distinct opening-process IDs, exact
publication error codes and nonempty committed-WAL sources.

The image was ejected (`disk34`) and `/private/tmp/usagi-disk-space.rXts7C/storage.asif`
was removed. The frozen schema SHA-256 remains
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`;
all five pinned writer/reader/store checksums pass. No production storage or model changes.
Earlier capture pressure, physical devices, Data Protection and interruption inside file
publication remain open. This simulator matrix does not establish those cases.

Final repository-wide Mainboard lint passes all 436 files without rewrites or failures
(`OpeningSpace-FullMatrix-FullLint-20261022.log`). The initial changed-file lint also passes;
it is not counted as the repository-wide gate.

### Full-refresh reconciliation and current external gates

The API-cache audit confirms that only subjects use incremental wire responses. Assignments,
materials, statistics, level history, voices and SRS systems use complete collections.
`applyDownload` replaces account state and removes absent rows while preserving pending
answers, notes and active-session recovery content. Additional cursors are not required to
provide reset reconciliation and would add a separate deletion-reconciliation obligation.

`fullReplacementRemovesStaleRowsButRetainsPendingRecoveryContent` now uses an on-disk store
and checks its existing assertions through a newly opened actor. Removed subjects disappear
except the hidden pending-recovery subject; notes, statistics, voices, audio, level history and
cursors are cleared, while the pending review survives. This is actor/container reopening in
the same process, not a process-crash or real-account reset claim.
`FullRefresh-Reopen-20261022.log` passes all 12 NativeRefreshTests and 13 DownloadTests
functions. `FullRefresh-Reopen-Lint-20261022.log` passes 436 files without rewrites/failures.
Production behavior and frozen schemas remain unchanged; one stale importer comment is corrected.

Read-only access checks after commit `0faee1a3`:

- `Acceptance-Devices-20261022.txt`: the physical iPhone remains offline; the Mac and
  simulators do not substitute for paired-device acceptance.
- `Acceptance-Signing-20261022.txt`: zero valid signing identities.
- `Acceptance-Mainboard-Pin-20261022.txt`: GitHub returns HTTP 422 for the exact Mainboard
  commit referenced by all five Actions checkouts. The local workflow cannot establish a
  successful hosted run until its required tool commit is published.

No signing, push, distribution, normal-account exercise or device installation was attempted.
The current task table now reflects the already-passing iPhone/iPad endpoint journeys and
Mac keyboard fallback. Historical checkpoint paragraphs retain their original chronology.

### Adaptive iPad/iPhone Home contrast audit

The initial iPad run failed before auditing content because the test unconditionally required
an iPhone-style bottom tab bar. `HomeContrast-iPad-20261022.log` and
`test-2d689f6646284f05a62231a8b68cd6f0.xcresult` retain that failure. Its capture confirms the
native iPad navigation controls appear at the top.

The existing audit now derives its viewport from the Home collection intersected with the
app frame, the navigation bar and any intersecting bottom tab bar. It requires a positive
viewport and fully contained forecast/community elements. The contrast policy is unchanged:
visible active content must pass; only recorded off-viewport and verified disabled-control
exceptions are accepted. No platform check, color change or suppression was added.

- iPad: `HomeContrast-iPad-Adaptive-20261022.log`,
  `test-005bfb4600264dc09dd7bbdc5a6a1f74.xcresult`, one pass, no skips/failures, 45.153 s.
- iPhone: `HomeContrast-iPhone-Adaptive-20261022.log`,
  `test-8fa3d4bfad44483585e68ff9e62a74ac.xcresult`, one pass, no skips/failures, 53.479 s.
- `HomeContrast-Adaptive-Lint-20261022.log`: 436 files pass without rewrites.

Both runs sweep light and dark Home content through the final community link. The iPad
lower-section captures were inspected in
`HomeContrast-iPad-Adaptive-Captures-20261022`: light
`0A35E076-732F-4E44-8685-D12F7DCEAB56.png`, dark
`BCBC54C7-2CCF-4838-A805-D77BC1E975D3.png`. Level rows, item-spread counts, recent-item
empty states and the community link remain readable and reachable. This covers normal-size
portrait Home in the synthetic fixture, not full accessibility, higher-contrast settings,
VoiceOver, Reduce Motion, landscape or other pages.

### Detailed forecast follows local time

A source audit found that Upcoming reviews reloaded only for account/snapshot timestamp or
lesson-preference changes. Unlike Home and Stats, it did not advance while left open.
The regression uses the existing fixture assignment due 30 seconds after launch, requires
current-hour zero and future-hour one, then waits without interacting or refreshing.

Before repair, `Forecast-Clock-Before-20261022.log` and
`test-ea971edadd92482bbfa89cbb7f1d3e26.xcresult` fail after the 100-second predicate timeout:
zero/current and one/future remain. The shared view now uses `TimelineView(.everyMinute)`
and the model's existing data revision in its request identity. This also observes snapshot
changes that retain the saved timestamp. Successful calculation clears a previous error.
All reads still use the existing availability query; vacation/pending-work guards and
cancellation checks remain. No network request, persistent model or timer service is added.

After repair, `Forecast-Clock-After-20261022.log` and
`test-4ad3e5a9aa7d422186acbc09ed2289f1.xcresult` pass both the new regression (56.051 s)
and existing per-hour stage/subject breakdown and Back journey (16.007 s), no skips/failures.
The new test requires the future row to disappear, the current count to become one and
its Kanji breakdown to remain accessible. `Forecast-Clock-Lint-20261022.log` passes all
436 files. These iPhone simulator checks establish the local-clock behavior, not real-account
forecast calibration, physical-device performance or every forecast error-recovery path.
