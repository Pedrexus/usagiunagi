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
