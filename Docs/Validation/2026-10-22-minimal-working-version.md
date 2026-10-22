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
