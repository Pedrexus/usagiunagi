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
