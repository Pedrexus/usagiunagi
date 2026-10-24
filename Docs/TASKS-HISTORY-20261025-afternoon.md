# Current modernization tasks

Updated October 25, 2026. **The modernization is not complete.** This is the current
decision and work ledger; the [October 25](TASKS-HISTORY-20261025.md) and
[October 24](TASKS-HISTORY-20261024.md) archives preserve earlier receipts, failed
experiments, comparisons and source scopes.
Historical statements such as “current,” “latest” or “passes” in that archive are
dated evidence, not a replacement for the remaining requirements below.

Work in `/Users/pedro/Developer/projects/apps/usagiunagi`, branch
`codex/swiftui-27-curriculum`. Commit locally; no PRs, app pushes or distribution.
Only Mainboard publication through `fa467e07a71b26876f48b2dd3c273b5e3f14c1fd` was approved.

Focused suite maintenance (October 25): `lessons` now includes related-subject
scrolling and largest Dynamic Type; `review-modes` includes voice backgrounding
without grading. The full UI suite already included these tests. Mainboard app
discovery loads the amended manifest and all declared ReviewFlowTests selectors
resolve to source methods. Receipt: `.build/Results/Focused-Suite-Registration-20261025.log`.
This configuration-only change does not represent another simulator test run.
Physical-device checks remain deferred at the owner's request.

Lesson picker lifecycle (October 25): Start lessons now uses a SwiftUI `.task(id:)`
owned by the picker instead of an untracked button task. Pending subject IDs also
supply the busy state. NativeLessonView checks cancellation after fetching available
lessons and before replacing the selection; cancellation does not present an error.
iPhone fixture tests for retained selection/unfinished quiz drafts and wrong-answer
rules/completion both pass in `test-397088e320f64ef19c3c748755e8b503`, zero warnings
or skips. Two-file lint passes. Receipts: `.build/Results/Lesson-Picker-Lifecycle-20261025.log`
and `Lesson-Picker-Lifecycle-Lint-20261025.log`. These normal-flow regressions do not
inject the precise close-during-read race. Physical acceptance remains deferred.

Current iPad lesson acceptance (October 25, source `0d2b12cf`): the actual named
Mainboard command `mainboard app test usagiunagi --suite lessons --device ipad`
passes all five tests in `test-da11e48086d34743ae035bb407b12324`: largest Dynamic
Type, page/swipe/quiz navigation, retained selection and unfinished draft,
wrong-answer/completion rules, and related-subject scrolling. Zero failures,
skips, compiler/analyzer warnings or reported runtime warnings. Retained tooling
source `7dfce9f` was used; this does not establish the live Mainboard reorganization.
Normal and XXXL portrait screenshots were inspected: heading, Start quiz and
footer Quiz remain visible/readable; reading stacks at XXXL. The fixture has sparse
content, so this is not full-catalog visual parity or landscape/multitasking acceptance.
Normal iPad launch restored. Receipts: `.build/Results/Lessons-Named-iPad-20261025.log`,
`Lessons-Named-iPad-20261025/manifest.json`, and `Lessons-Named-iPad-Normal-20261025.log`.

Statistics calendar acceptance (October 25): added a parameterized regression for
New York's spring 23-hour and autumn 25-hour days. It checks exact local chart dates,
overdue-at-now separation, midnight attribution and exclusion of day eight; no
production calculation changed. All 12 StudyStatisticsTest functions pass (13
parameterized executions) in `test-5942be029cac4d6695c8a481e735502c`, with zero
failures/skips/reported warnings. Final one-file lint passes after a line-wrap-only
format fix. Receipts: `.build/Results/Statistics-DST-20261025.log` and
`Statistics-DST-Final-Lint-20261025.log`; the initial formatting failure is retained.
This verifies calendar bucketing, not real-account forecast calibration or exam readiness.

Subject-settings cleanup (October 25): removed the unused single-implementation
`StudySubjectPreferenceStore` protocol; observation, defaults injection and the iCloud
callback remain intact. Both subject-preference suites pass (6 tests, receipt
`test-23dd9107e33544d6973e38a03810aabd`); one-file lint passes. Logs:
`.build/Results/Subject-Settings-Simplify{,-Lint}-20261025.log`. This verifies local
merge/reopen behavior, not deferred physical iCloud delivery.

Live Mainboard acceptance (October 25, app `82431eec`): installed CLI 0.5.6 now
loads `app list`, builds `mainboard app build usagiunagi --device mac
--configuration Release --timeout 240`, and runs the declared `audit-release-mac`
task without retained-source or DEVELOPER_DIR overrides. Build
`build-33702d0a1bdb49f9b693b5f0243d4223` succeeds with zero reported compiler/analyzer
issues; Xcode separately logs its no-AppIntents-dependency metadata notice. Bundle
audit has no violations (localized names/icon, microphone metadata, forbidden
FMDB/test resources). Logs: `.build/Results/Live-Mainboard-Mac-20261025.log` and
`Live-Mainboard-Mac-Bundle-20261025.log`. Mainboard's checkout remains extensively
modified by concurrent work; no Mainboard files were edited or published. This
closes the current live Mac build/audit import blocker, not hosted CI, full tooling
acceptance, signing or current Mac UI acceptance.

## Requirements and status

“Implemented” means source exists with the cited scoped evidence. It does not mean
all platform, physical-device or release acceptance is complete.

| Requirement | Implemented / verified scope | Remaining acceptance or decision |
| --- | --- | --- |
| One iPhone-first app | Shared SwiftUI root, account model and SwiftData store; adaptive tabs/sidebar, toolbars and forms. App-owned UI/services moved out of StudyUI/StudySpeech into App. Tests share App/Tests. | Wider iPad/Mac layouts, keyboard/IME, window restoration and original-app usability comparison. Preserve required bridges. |
| Lessons and reviews | Selection, interleaving, teaching, quizzes, Anki, correction, wrap-up, notes, synonyms, exclusion and summaries have scoped fixture acceptance. All 57 logged passes from the interrupted iPhone run now map to finalized receipts; five URL-driven journeys also pass. | Physical input/caret/IME, broader device layouts and final original-Tsurukame parity. Receipt reconciliation spans source revisions, not one full current-source suite. |
| WaniKani design | Pink/blue/purple subject colors, compact review/lesson flow, native typography, SF Symbols and glass controls; owner screenshots guide the design. Note-editor keyboard warning fixed on iPhone/iPad. | Full dark/light/high-contrast/Dynamic Type and VoiceOver coverage; broader iPad/Mac rendering. Two high-contrast voice journeys are accepted, not every screen. |
| SwiftData-only study storage | FMDB/importers retired. Native actor, outbox, frozen V1, generation validation/adoption and recovery. Mac/iPhone corruption, interrupted saves and bounded disk-full matrices have receipts. Mac base/WAL source-copy ENOSPC, incomplete family capture and final publication before fsync recover exact records. | Interruption inside a single file copy, APFS clone failure, iOS capture/publication, physical pre-answer interruption, Data Protection/power loss and real-catalog/device performance. See storage invariants below. |
| Offline sync and recent mistakes | Durable pending work, account/origin fences, rollback/retry, refresh cancellation and 24-hour mistake projection have scoped tests. | Real account permissions/delivery, signed iOS/Mac KVS identity, multi-device/account transitions and offline recovery with real data. Never perform live exercises without authorization. |
| Continuous bilingual voice | English/Japanese selection, pause-to-submit, automatic advance/mistake/retry and keyboard fallback. Kana script is preserved; recognizer alternatives can disambiguate without an answer key. Actual Mac file-fed capture/controller works. | Live microphones, language-model readiness, latency, interruptions/audio routes and human recognition across physical iPhone/iPad/Mac. Synthetic capture and generated audio are not live speech acceptance. |
| Watch reviews and widgets | SwiftUI Watch app, foreground voice loop, phone recognition/grading bridge, four WidgetKit families and atomic snapshot. ClockKit migration code removed. | Physical paired Watch/phone transport, permissions, reachability, locked/background phone behavior, signed App Groups and installed-face/cache upgrades. |
| Credible statistics | Swift Charts, focus prioritization, held-out pace comparisons, school/Jōyō/estimated JLPT and verified Kanken memberships. Pending subjects separated. Explicit chart accessibility values added. | Full-account calibration, real-catalog performance and spoken chart acceptance. Character coverage and pace are not exam-pass predictions. |
| API/cache/mock data | WaniKani API to SwiftData; subject deltas merge safely; other endpoints use complete downloads. Parquet/export tooling retired. 357-item levels 1–3 preview is display-only. | Permitted real-account/offline verification and measurements. Conditional HTTP requests remain optional measured work, not a required new cache layer. |
| Settings and private iCloud | One page groups six WaniKani controls and app preferences; debounced account-fenced updates. Independent private SwiftData schema covers 46 portable choices with per-field reconciliation and study deferral. | Owner container registration, signed entitlements, cross-device/background/account-change delivery and real WaniKani permissions. Device-specific choices stay local. |
| Native media/services | Shared settings, fonts/audio, diagnostics, notification preferences and background scheduling with scoped iPhone/iPad/Mac evidence. Mac appearance mutation and fixture font/audio download, cancellation, retry and deletion have direct native checks. | Other Mac preference writes, relaunch restoration, real playback/network and physical notification/background/audio behavior; signed Keychain continuity. |
| Rename/icon/localization | Fork remote is Pedrexus/usagiunagi. Localized 兔鰻/usagiunagi names and shared layered kanji icon compile; earlier bundle/static exports checked. | Physical Home Screen/Dock/Watch appearance variants and signed identity acceptance. Store listings/distribution require separate owner authorization. |
| Lean code and modern Swift | Retired UIKit screens, Go/Objective-C/FMDB/protobuf/importers/assets removed; redundant app initializers reduced. Shared modules remain where persisted identity requires them. | Continue only evidence-based simplification without losing functionality or frozen data. Resource and final Release acceptance remain scoped. |
| dataclass / constructor helpers | Separate reusable library and SwiftData/macro tests implemented. App pilot saved only three lines, so native constructors retained. Weak lifetime boundaries audited. | Publication and a larger measured benefit before app adoption; physical-service lifetime checks. No frozen-schema changes for boilerplate savings. |
| Mainboard rules/workflow | Swift rules, formatter/SwiftLint, inventories, native builds/results and 28 named app suites. Optional pytest collection is isolated; two regressions pass. Installed CLI/build/launch work after the dispatcher repair; compact-report documentation links are corrected locally. | Latest October 25 check reports 240 signals; 77 Swift migration signals have contextual review. Continue general-finding triage. Collector/report fixes remain within the pending reorganization; integrate without staging others' edits. Newer publication needs approval. |
| GitHub Actions / final tests | Bounded native lanes, pinned packages, storage matrices and product audits declared. All five tool checkouts pin published fa467e0. Local app/rules commands are newer than that pin. | Hosted run not performed: app push is not authorized. Newer Mainboard publication also needs approval. Tests run after implementation/manual repairs; preserve full assertion scope. |
| Launch/reopen reports | iPhone native root, warm links, held refresh, account flows and normal simulator launch have finalized receipts. One pasted crash was SpringBoard, not the app. | Current broader Mac/window restoration and any newly reproduced matching app crash. Latest Mac UI attempt failed to connect its runner before executing tests. Do not equate compilation with launch acceptance. |

## Remaining work

Pinned CI compatibility review: all workflow Mainboard checkouts still name authorized
`fa467e07a71b26876f48b2dd3c273b5e3f14c1fd`; the workflow correctly uses that revision's
`analyze` namespace. Its exact Git source was extracted to `/tmp/usagi-mainboard-fa467e0`.
With Mainboard's installed interpreter/dependencies, that source validates the current
manifest and constructs `PixiManifest` successfully (19 tasks; test, both Release builds
and both bundle audits present). New `[apps]` metadata does not require a schema edit
for those old task routes. Receipt: `.build/Results/CI-Pinned-Manifest-Runtime-20261025.log`.
The first attempt used PATH's unrelated Python without patos and failed before validation;
its `CI-Pinned-Manifest-20261025.log` is retained. No workflow/pin changes were needed.
This is manifest/compiler compatibility, not a clean `uv sync --locked` environment,
all CI command execution or hosted Actions acceptance; no push or dispatch occurred.

Current-source Release follow-up: both iOS Simulator and native Mac builds and declared
bundle audits pass with the parent-path storage fix. Details are in Current Release
products below. Earlier comments that Release predates this fix are historical; runtime,
interruption and physical-device scopes remain distinct. Live `mainboard --version`
returns 0.5.6 again, but these builds/audits deliberately used retained `7dfce9f`; this
is not publication or full validation of the concurrently changing Mainboard checkout.

Storage integration at `c2c7e62c`: the full Shared run passes 197 core plus 172
persistence test functions across 52 suites (369 total), including the parent-path
regression. On iPhone 18 Pro / iOS 27, the exact frozen-adoption test passes both base
and committed-WAL parameters (`test-8575df5ce4e049419de77a91fa27b996`), preserving fields
and writes through reopening. Receipts: `.build/Results/Store-Parents-Full-Shared-20261025.log`
and `Store-Parents-iOS-Adoption-Exact-20261025.log`. The first iOS invocation omitted
`(committedWAL:)` and selected zero tests; Mainboard refused it, and its
`test-fd6bed9ea9c84d31bfbccb859394119b` receipt remains unsuccessful evidence. This
closes ordinary iOS adoption integration for the new check, not direct iOS symlink cases,
iOS interruption during capture/publication, physical durability or Release packaging.

Store parent-path validation: startup previously accepted a symlinked `generations`
or `preparations` parent despite validating individual images. Both disposable cases
reproduced acceptance before the fix. Opening now validates those existing parents with
`entries(in:)` before reading the selection or opening a store. Three production lines;
no schema, frozen fixture, serializer or saved-data format changes. The full
`StudyStoreOpeningTests` suite passes (eight functions, including parameterized cases),
including exact redirected-target/selector byte preservation, interrupted preparation,
cancellation, corruption rejection and reopen behavior. Final two-file lint passes.
Receipts: `.build/Results/Store-Parent-Redirect-{Before,After,Final-Lint}-20261025.log`.
The initial formatting failure and formatter output are retained. This is a macOS
Swift Testing check using retained Mainboard `7dfce9f`; it does not prove adversarial
concurrent filesystem replacement, iOS execution, mid-copy interruption or physical durability.
Release/runtime receipts above predate this storage change.

Voice background lifecycle: the new isolated iPhone regression starts listening,
presses Home and reactivates the app, then verifies keyboard mode, the same subject
and meaning question, zero completed items and no listening control. Explicit voice
restart and finalization then advance to Reading. It passes in 20.829 seconds
(`test-18fc074083a74b38a54b9cf1093ed11a`, no failures/skips/runtime warnings); one-file
lint passes. No production change was needed. Receipts:
`.build/Results/Voice-Background-20261025.log` and `Voice-Background-Lint-20261025.log`.
This uses the synthetic recognizer and retained Mainboard `7dfce9f`, not live microphone,
audio-route interruption, delayed post-cancellation callback injection or physical-device
acceptance. Normal simulator launch was restored.

Current native Mac checkpoint at `5fc4cc34` (production `f5e27dde`): Release
`build-30360c5444be4184b72b5f1900b0050a` passes with zero reported compiler/analyzer
issues. The prior Release process quit normally. PID 71723 opened one responsive
Account window, its display-only preview opened Subjects, and a fresh dark catalog
screenshot was inspected. Normal termination completed; PID 72376 reopened one
responsive Account window. No account connection or exercises. Receipts:
`.build/Results/Lesson-Lifecycle-Release-Mac-20261025.log` and
`Mac-Lifecycle-*-20261025.log/png`. Signed-account/session/window restoration remains open.
The live Mainboard checkout broke during this check (`dispatch.agent.snapshot` import
failure before preview interaction); remaining bounded native checks used the retained
`7dfce9f` snapshot with process-local Xcode selection. The failure log is preserved as
`Mac-Lifecycle-Preview-Open-20261025.log`; this is not a repaired/published tool revision.

Current Mainboard triage at `f5e27dde`: retain the native settings-opening bridge in
`NotificationSettingsSection` (UIKit/AppKit provide the actual application/settings
integration); retain the explicit destination switch in `StudyRootView` (typed routes,
account gating and feature-specific dependencies); retain Katakana's explicit action
switch (different submit, retry, reveal and Anki semantics). Splitting these solely to
reduce reported complexity would add indirection without removing behavior. Snapshot
field repetition is deliberate exact-schema validation against the frozen baseline;
do not replace it with a shared encoder that makes independent validation circular.
Empty/directory-path findings include Xcode/SwiftPM-generated configuration and required
package/workspace layout, not obsolete app modules. This is scoped triage of these
findings, not closure of all 240 signals. No suppressions or source changes were made.

Lesson reload ownership: all four `Task { await load() }` actions in
`NativeLessonView` now change a refresh identity consumed by its existing SwiftUI
`.task(id:)`. Back, completion and retry use the same cancellable lifecycle as initial
loading; no controller/task registry or platform branch was added. Draft/selection
retention and wrong-answer/completion pass on iPhone 18 Pro
(`test-cf1eb844e7d641919ac783289cbde8fc`, two tests), and one-file Mainboard lint passes.
Receipts: `.build/Results/Lesson-Reload-Lifecycle-20261025.log` and
`Lesson-Reload-Lifecycle-Lint-20261025.log`. This replaces the unstructured reload
ownership noted below; precise suspended-read cancellation and broader scene/account
transitions still lack deterministic acceptance.

Lesson load cancellation: after awaiting `store.session`, `NativeLessonView.load` now
checks task cancellation before mutating paused-session/batch state or calling
`openLessons`. Later store reads already had this boundary. This closes a source-level
cancellation gap without a new abstraction or schema change. Existing iPhone draft
retention and wrong-answer/completion journeys both pass
(`test-c3fddf58429f4ebba944bc2d61812e39`), as does one-file Mainboard lint. Receipts:
`.build/Results/Lesson-Load-Cancellation-20261025.log` and
`Lesson-Load-Cancellation-Lint-20261025.log`. These are surrounding behavior regressions;
they do not deterministically suspend/cancel the first database read. Unstructured
reload ownership and broader scene/account transitions remain review scope.

Simulator diagnostics investigation: the post-failure `simctl` lookup error is emitted
by Xcode's `IDETestOperationsObserverDebug`, after the actual assertion failure, not
by Mainboard's simulator inventory/launch. The system developer directory is
`/Library/Developer/CommandLineTools`; direct `xcrun --find simctl` fails, while
`mainboard proc timeout 15 /usr/bin/xcrun --find simctl` resolves
`/Applications/Xcode.app/Contents/Developer/usr/bin/simctl`. Mainboard's existing
process-local Xcode selection is effective. This identifies a tool-selection mismatch,
not proof of the collector's internal environment or a validated repair. Do not mask
assertion failures or add a second app build driver. Receipt:
`.build/Results/Simulator-Diagnostic-Tool-Selection-20261025.log`; original collector
failure retained in `Lesson-Related-Swipe-20261025.log`. Machine-wide tool selection
was not changed. Failed-test diagnostic collection remains a tooling limitation.

At `e49a9ae9`, iPad Pro 11-inch (M5) / iPadOS 27 passes all three targeted lesson
checks: normal/largest Dynamic Type with touch-target audits, teaching/quiz navigation,
and related-row gesture isolation (`test-3b4d96cb4d6a46be958e4784e6e2e522`; three tests,
zero failures/skips/runtime warnings). Both exported portrait screenshots were inspected:
Quiz text is visible, the largest reading row stacks, and both toolbar and footer actions
fit. This closes these specific iPad follow-ups for the control/gesture fixes below;
Mac gestures, multitasking, hardware input and VoiceOver remain unverified. Receipts:
`.build/Results/Lesson-Gestures-iPad-20261025.log` and its attachment directory.

Related-subject gesture fix: swiping the radical row in a teaching page also changed
its parent lesson (`test-379731d439854a928569627651ba943c`, reproduced before repair).
Replacing the parent's simultaneous gesture with a normal gesture lets child controls
handle their interaction first. The related-row regression and existing teaching/quiz
navigation both pass (`test-e1a6b3ef22e845239f800a728252567b`, two tests) on iPhone 18 Pro.
No new abstraction, platform branch or persistence change. Receipts:
`.build/Results/Lesson-Related-Swipe-20261025.log` (failure),
`Lesson-Related-Swipe-Priority-20261025.log` (pass). This verifies the fixture row and
ordinary page swipes, not every scroll extent, hardware input or platform.

Quiz gesture fix: a right swipe over an active lesson quiz previously changed the
lesson page. The added regression fails before the fix (`test-479b0a65de7a4344a5cde46854d1bd3e`).
The shared page gesture now requires a teaching-page index. Afterward both the navigation
regression and existing selection/unfinished-draft journey pass on iPhone 18 Pro / iOS 27
(`test-8666ef7123c54d1ca26b7a97b8cd2382`, two tests, zero failures/skips/runtime warnings).
Teaching swipes and explicit return from Quiz remain available; the durable session is
unchanged. Two-file Mainboard lint passes. Receipts: `.build/Results/Lesson-Quiz-Swipe-`
`{Before,After,Lint}-20261025.log`. Other-device gesture execution remains unverified;
the Release products below predate this small guard change.

Dark lesson accessibility: the expanded audit reproduced contrast failures on the
toolbar action and bottom Quiz control. The toolbar now uses adaptive system blue
with prominent glass; Quiz uses an opaque native prominent button with primary fill
and inverse background-colored text. WaniKani subject colors remain unchanged.
Final `test-70b8010292364d75969cf1ba71991ce8` passes contrast and sufficient-description
checks; the exported screenshot was inspected to confirm visible labels (an earlier
passing audit missed an invisible white-on-white label, which was corrected).
Contrast excludes only static text outside the measured content viewport, retaining
each exception: the sole final exclusion is Stats at y=768…820.33, clipped below the
viewport ending at y=780. Buttons and description checks are never excluded.
Receipts: `.build/Results/DarkLesson-Accessibility-Inverse-20261025.log`,
`DarkLesson-Inverse-20261025/` and `DarkLesson-Inverse-Lint-Verified-20261025.log`.
Earlier failed experiments remain in Results. At `dc6508d8`, the iPhone light-mode
normal/largest Dynamic Type test passes (`test-349274da6a904b3995f66d5882626457`,
41.163 seconds), including unsuppressed picker/teaching touch-target audits. Both
exported screenshots were inspected: normal Quiz has visible white text on black;
at largest text the footer scrolls horizontally and the top Start quiz remains fully
visible. Receipt: `.build/Results/Lesson-Controls-Light-Large-20261025.log` and its
attachment directory. Other-platform rendering and full VoiceOver acceptance remain open.

Mnemonic cleanup: `StudyMarkup` now uses compile-time typed Swift regex captures and
Swift string indices, removing `NSRegularExpression`, forced initialization and manual
UTF-16/`NSString` range conversion (four fewer production lines). Unicode-scalar
matching preserves combining marks next to tags. Six focused test functions pass,
including three new Unicode cases; 9,261 deterministic combinations match the parser
from `4dc0cced` exactly. No dependency or schema change. Receipts:
`.build/Results/SwiftMarkup-Final-20261025.log`, `SwiftMarkup-Parity-20261025.log/.swift`
and `SwiftMarkup-Lint-Verified-20261025.log`. This checks parser behavior, not every
rendered mnemonic or final platform Release builds after the change.
At `8da433c3`, iOS dark-lesson rendering passes
`test-fc7dc969c8ec4c6dad5487a399d22fb7` (13.931 seconds); the fresh exported screenshot
was inspected for colored mnemonic spans, bold text, kana and the compact lesson
controls. Native Mac Release build `build-295150747b2e43ffbbfa0e13463ba19b` passes with
zero reported compiler/analyzer issues, including the adaptive reading style. Receipts:
`.build/Results/SwiftMarkup-DarkLesson-20261025.log`, its attachment directory and
`SwiftMarkup-Release-Mac-20261025.log`. This closes those specific integration checks,
not every mnemonic or current iOS Release acceptance.

Statistics source review at `7b07c322` traced `StudyStore.snapshot` and refresh projection
through `StudyMetrics` to dashboard/coverage rendering. Pending subjects are removed from
stage assignments and separately identified in coverage; pending uploads suppress date
scenarios. Empty history produces no accuracy/pace, fewer than three eligible levels
produce no pace, and held-out estimates use only earlier completed levels with at least
three training and three validation levels. Vacation/elapsed ranges suppress forecasts;
coverage uses the complete reference denominator and explicitly disclaims exam-pass
prediction. Existing API validation rejects negative answer counters. No new defect was
found in these paths, so no calculation changes or unchanged test reruns were made.
Real-account calibration and performance remain open; this is a source audit, not proof
of live statistical accuracy or all edge cases.

1. Integrate the verified local Mainboard collector and report-link fixes into its pending tool work.
   Permanent report regressions now live in Mainboard's
   `integration/analysis/test_finding_report.py`: four cases pass, preserving complete
   documentation URLs, distinct targets and grouped finding values/counts. Receipt:
   `.build/Results/Mainboard-Report-Regression-20261025.log`. They depend on the pending
   Report implementation and must land with it, not as a broken standalone commit.
   The earlier dispatcher repair enabled builds/launches. During the later Mac media
   check, the changing live checkout failed startup with missing `mainboard.fleet.batch`;
   bounded inspection continued through the preserved committed 7dfce9f snapshot.
   Subsequent live recheck found the import corrected by the concurrent reorganization;
   app discovery and a declarative Mac Release build pass (receipt below).
   Coherent commit/publication remains pending. Continue contextual triage without
   deleting required bridges or frozen evidence. Preserve unrelated in-progress
   changes and do not publish newer tooling without approval.
   Reviewed the three `ALL-DUPL0003` signals comparing `WaniKaniPreferences.swift`
   with `StudyLessonPreferences.swift`: retain explicit field comparisons. The former
   builds an optional server PUT delta; the latter applies local edits and normalizes
   lesson constraints. A generic diff helper would hide these different contracts.
2. Finish supported local storage failure boundaries using marked disposable stores
   and bounded volumes. Avoid repeating rejected calibrations preserved in the archives.
   The existing iOS `interruptedOpening` harness observes persistent-store attachment
   during verification/candidate opening. It cannot interrupt earlier file capture or
   final selector publication; rerunning it does not close those two remaining gates.
3. Finish adaptive layout, original-app comparison and keyboard/IME/accessibility
   acceptance. Fix demonstrated regressions before rerunning affected checks.
   Do not retry unchanged Mac runner or Device Hub hangs indefinitely.
   The earlier iPad keyboard timeout is superseded by a full 35.374-second pass at
   `b875a762`, test-254a0e8e65b04a989340e766afb1346e. Device Hub's verified iPad window
   had hardware-keyboard simulation enabled; it was disabled before launch and the
   settled menu state confirmed. No mid-run toggle or assertion changes were used.
   Visible-keyboard geometry passes before/after Quick Settings, the draft survives,
   and both answers reach the saved-session screen. The exported screenshot was
   inspected. Receipts: `.build/Results/iPad-Keyboard-Preconfigured-Review-20261025.log`
   and `iPad-Keyboard-Preconfigured-20261025/`. Original timeout diagnostics remain;
   their exact cause is unproven. Physical IME and broader layouts remain open.
   Native app inventory reported Device Hub PID -1 despite live PID 96505 and working
   AX menus: verify process/accessibility state before treating that inventory as absence.
4. When the owner resumes physical checks, verify voice, Watch, iCloud, Keychain,
   notifications and device performance with the required signing/account setup.
   Real-account statistics calibration also remains open; local mocks cannot close it.
   Do not request the deferred setup again in the meantime.
5. Reconcile final source-specific checks and Release/resource/icon evidence after
   changes. Hosted CI and distribution are gated by separate publication authorization.

Keep checks bounded and serialize UI runs and shared derived-data directories.
Re-run accepted scopes only for a relevant source change, failure or unresolved risk.

## Storage invariants

- Lesson accessibility follow-up: added unsuppressed touch-target audits on the picker
  and teaching page at normal and largest Dynamic Type. Initial pass
  `test-2929774e817e4730aa3a60790dcfdb67` still exposed a visual issue: the two-column
  reading row split its label and kana unnecessarily. Reading labels now stack only
  at accessibility sizes using a local SwiftUI `LabeledContentStyle`; normal sizes
  retain the system layout. Final `test-d2fe48c3264f4bc3bb4cbc5b6f93cf20` passes and
  the exported largest-text screenshot was inspected: label and kana each fit a line.
  Logs/attachments: `.build/Results/Lesson-ReadingLayout-20261025*`; final two-file lint
  passes. This is iPhone fixture coverage, not VoiceOver or all-device acceptance.
- The same updated lesson test passes on iPad Pro 11-inch (M5), at `34c7b00d`:
  `test-a2247074e44c4b8e8c4ff7ef6be52f91`. Both exported screenshots were inspected:
  normal text retains the compact two-column reading, largest text stacks it without
  splitting the label or kana, and lesson navigation/quiz controls remain reachable.
  Touch-target audits pass on picker and teaching pages at both sizes. Receipts:
  `.build/Results/Lesson-ReadingLayout-iPad-20261025.log` and its attachment directory.
  This lesson check does not establish physical IME or multitasking/VoiceOver acceptance.

- Release verification at `d851b653`, including both recent sync fixes: iOS build
  `build-7f2928eba6c74e8d8853cb647dc66c4b` and native Mac build
  `build-44655a85719949028f7d9879b6095319` succeed with zero reported compiler/analyzer
  issues. Both declared bundle audits return no violations for retired dependencies,
  bundled test/store fixtures, localized names, icon metadata and microphone usage
  description. Receipts: `.build/Results/SyncFences-{Release,Bundle}-{iOS,Mac}-20261025.log`.
  This supersedes pre-fix Release build evidence, not runtime or physical acceptance.

- Recent-mistake sync error publication now uses the same account, observed Apple
  identity epoch and cancellation fence as successful reads. A new malformed-read
  regression reproduced a stale error after an Apple account change before the fix
  (test-651d2198f72e41239da5a0f1f0527b5b). Afterward all 11 functions / 12 cases pass
  (test-f99492e49a3340ada60732f7f2aa499b), including malformed current-account data,
  quotas, unavailable cache retry and both identity-change variants. Two-file lint
  passes. Logs: `.build/Results/MistakeSync-StaleError-{Before,After,Lint}-20261025.log`.
  These are isolated simulator fixtures, not signed iCloud delivery acceptance.

- Preserve frozen `StudySchemaV1.swift` hash
  `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`, the original
  fixture, writer archives and nested stored type identities. They are required
  compatibility evidence, not dead code.
- Original/retained data and abandoned preparations survive failed adoption. Retry
  uses a fresh candidate. Grading penalties and exactly one pending answer survive.
- No V2 is needed to finish the current app. Bind historical decoders into the actual
  upgrade path and close applicable G7 gates **before** any future schema/payload
  change. P5/P6 refinements require measured benefit; do not add another storage layer.
- October 22 finite reserve calibration did not hit source-copy ENOSPC. October 24
  file-size limiting passed capture, failed verification, then recovered all 38 records
  in fresh processes. Neither closes mid-copy or capture-specific disk-full acceptance.
- [Probe guide](../App/Tests/PersistenceProbe/README.md), [migration specification](Migration.md)
  and [storage evidence](Implementation/2026-10-21-frozen-ios-and-review-focus.md)
  define the exact matrices and limits.
- October 25 cross-volume APFS capture failed with actual ENOSPC for base and
  committed-WAL sources. Each recovered 38 exact records in two fresh processes,
  preserving sources and failed preparations. APFS clone failure, interruption inside
  one file copy and iOS capture remain unverified. See the
  [scoped receipt](Validation/2026-10-25-source-capture.md).
- Mac base/WAL interruption inside final publication now passes at the pre-fsync
  breakpoint: each restores 38 exact records twice, then an abrupt first answer/note
  write restores 39 records twice. Original/retained files and selection stay unchanged.
  No production hook or schema change. This closes that Mac process boundary only;
  iOS publication interruption, nonzero mid-copy and power loss remain unverified.
  See the [debugger receipt](Validation/2026-10-25-source-capture.md#interruption-inside-final-selector-publication).
- Same-volume base/WAL capture interruption after the first real file copy now passes:
  the 180,224-byte abandoned capture stays unchanged, retry chooses a fresh candidate,
  and two fresh processes restore all 38 records. In the WAL case neither sidecar had
  been copied. This verifies the incomplete family boundary, not interruption inside
  one file's copy or APFS clone failure. See the
  [capture receipt](Validation/2026-10-25-source-capture.md#nonempty-interruption-during-source-family-capture).

## Owner decisions and platform boundaries

- Reduce Motion system-setting acceptance is explicitly deferred by the owner on
  October 24. Do not repeatedly ask to enable it or count the skipped test as passing.
- iPhone Duo-specific work remains deferred. The dismissed Coverage popup stays closed.
- WaniKani remains authoritative for learning data. Private iCloud contains app-owned
  preferences only, separate from the local study store and its outbox.
- Preserve Japanese IME UIKit input and native audio, notifications, lifecycle,
  WatchConnectivity and Core Data generation-validation/copy boundaries until an
  equivalent replacement is demonstrated. See [architecture](Architecture.md).
- Do not remove features to remove their implementation. Do not add speculative AI
  grading, a second cache/storage layer, or an unpublished macro dependency to save
  a few lines. Optional read-only AI/intents are not required grading behavior.
- Computer-use Device Hub inspection stalled for hours despite a requested timeout.
  Avoid that path. Latest Mac UI runner also failed to connect; earlier successful
  Mac receipts retain their own source scopes.
- October 25 device discovery finds an iPhone 16 Pro Max available/paired and the
  three existing simulators. `security find-identity -v -p codesigning` reports zero
  valid identities. The owner explicitly deferred physical-device checks. Do not
  request signing setup again until the owner resumes them. Live voice, paired Watch,
  signed iCloud/Keychain and physical-device acceptance remain unverified.
- For stable read-only/Apple execution while Mainboard is being edited, the exact
  committed `7dfce9f` sources are extracted under `/tmp/usagi-mainboard-7dfce9f`.
  `PYTHONPATH=/tmp/usagi-mainboard-7dfce9f/src mainboard ...` successfully runs the
  device/signing checks. It changes neither installation nor checkout; it is not a
  repair or publication of newer `app`/`rules` behavior. Restore that exact snapshot
  from Git if temporary files disappear. The subsequent dispatcher syntax failure
  has now been repaired in the live checkout; normal CLI/build/launch work again.
  Keep the snapshot as a fallback, not the default required path.

## Latest evidence index

The [October 25 archive](TASKS-HISTORY-20261025.md) preserves the full ledger through
2f3b2970 byte-for-byte; the [October 24 archive](TASKS-HISTORY-20261024.md) preserves
earlier history. Local .build/Results receipts remain intentionally untracked and
must not be deleted as disposable build output. These summaries retain source scope:

| Scope | Latest accepted evidence | Limits |
| --- | --- | --- |
| Grading and storage | At c2c7e62c: 197 core + 172 persistence functions pass across 52 shared suites. iPhone frozen adoption passes both base/WAL variants (test-8575df5ce4e049419de77a91fa27b996). Earlier 6da3570a native review-store evidence covers 13 functions, including alternate-kana retries/outbox. | Shared logic and scoped simulated adoption; no physical recognition, signed transport or complete interruption matrix claim. |
| Automatic sync account fences | After three awaited account-state reads, the worker now checks account identity before applying refresh state, notices or retry scheduling. All 18 `AutomaticSyncTests` pass on iPhone 18 Pro / iOS 27, including disconnect during read/write, offline recovery, uncertain writes, throttling and scene ownership. Receipt: test-c8106b43bef043adbbbd04ec0703c098; logs: AutomaticSync-AccountFence-20261025.log and AutomaticSync-AccountFence-Lint-20261025.log. | Existing regression suite and source-level suspension-boundary audit; no deterministic interruption inside those three database reads, real-account or physical transport claim. Release integration is covered by the current products row. |
| Current Release products | At c2c7e62c: iOS build-9c5e2a1d099e4ae9a659f3af0882948a; Mac build-6a7777cbd28e45998d0175feaebd5559. Both report zero compiler/analyzer issues. Both bundle audits pass localized names, icon metadata, microphone description and forbidden retired-symbol/frozen/test-resource constraints, with no violations. Receipts: Store-Parents-Release-{iOS,Mac}-20261025.log and Store-Parents-Bundle-{iOS,Mac}-20261025.log. | Retained Mainboard 7dfce9f; unsigned local products, not signed distribution or physical visual acceptance. Live CLI version lookup succeeds again, but does not prove the pending tool revision integrated. |
| Repository enforcement | At f5e27dde: explicit `mainboard lint --check .` checks 449 files, no rewrites/failures (Modernization-Repository-Lint-20261025.log). `mainboard rules check .` reports 240 findings (Modernization-Rules-20261025.log). | Initial no-path lint checked zero changed files and is not repository evidence. Rule findings require contextual review, not blanket suppression. |
| iPhone layout | test-22ced2841c594fb99ba6ef315844195f: catalog paging/hidden answers/stages and inline pace comparison pass; fresh screenshots inspected. | Before the grader fix; same catalog/chart layout. |
| iPhone continuous voice | At 09276bee (production grader 0f6213a1): test-52368b7149b04c70a182887a4443ea0b passes all three journeys: both answers without taps, unclear-kana retry without grading, and mistake recovery without taps. Fresh inline-reading screenshot inspected; normal simulator app restored. Receipts: .build/Results/iPhone-Voice-Kana-20261025.log and iPhone-Voice-Kana-20261025/manifest.json. | Fixture recognizer; no live microphone or physical-device claim. Screenshot confirms subject color, reading strip and inline listening/keyboard controls, not full original-app parity. |
| Mac continuous voice | Debug build-d133fa1d8a52471d979d922e7ca54396 with current grader: three isolated native journeys required only starting reviews and enabling voice. Correct answers reached 100% / 1 of 1; unclear kana showed correction with submission disabled, retried and reached 100% / 1 of 1; a wrong meaning showed the expected answer, continued automatically and retained 0 of 1 in the saved summary. Bounded native observation logs: .build/Results/Mac-Voice-{Current,Repeat,Mistake}-*-20261025.log; exact observer and inspected mistake-summary screenshot retained. Fixtures exited; normal Release app focused. | Synthetic recognition, not live speech, physical transport or XCTest runner acceptance. Read-only observation after activation introduced no answer/advance actions. |
| Mac layout/navigation | Native isolated Debug build-d133fa1d8a52471d979d922e7ca54396: stats, inline pace, six settings/media routes inspected. Native chart labels and AXValueDescription verified. | Default light appearance; no VoiceOver speech, setting writes, downloads or playback. Normal account launch/preview/reopen has separate earlier evidence. |
| Current Mac startup | At f5e27dde: Release build-30360c5444be4184b72b5f1900b0050a; normal Account launch, display-only Subjects preview, graceful quit and fresh Account reopen verified. Dark preview screenshot inspected. Receipts: Mac-Lifecycle-*-20261025.log/png. | Unauthenticated startup only; no signed-account/session/window restoration. Live Mainboard import failure required the retained snapshot for later native checks. |
| Mac preference mutation | Debug build-d133fa1d8a52471d979d922e7ca54396, isolated settings fixture: selected Dark in the native picker, inspected the changed window, closed/reopened Settings and confirmed Dark remained selected. A separate process read `appearance=dark` from only the fixture preferences suite. Restored Light through the picker and inspected it, closed the fixture, and returned to the normal Release app. Receipts: .build/Results/Mac-Settings-Mutation-*-20261025.log/png. | Appearance only; fixture launch resets its suite, so this does not prove app-relaunch restoration, iCloud delivery, notification effects or other setting writes. Normal preferences were untouched. |
| Mac media controls | Same Debug build, synthetic font/audio fixture: font download/automatic selection, deselection, held-download cancellation, HTTP 503 retry presentation and confirmed deletion verified through native controls. Audio reached Up to date with 8 kB cached; disabling with Keep retained it, explicit deletion cleared it without clearing voice choices, and re-enabling restored 8 kB. Receipts: .build/Results/Mac-Media-*-20261025.log; exact inspector and screenshot retained. | No real network, playback, review-draft or relaunch claim. Initial live-tool failure occurred after opening a fixture; the duplicate snapshot launch was detected and closed before outcome inspection. Final fixture closed and normal Release app focused. |
| iPad | Large-text Home/lesson checks pass. test-254a0e8e65b04a989340e766afb1346e completes the full landscape review in 35.374 seconds with real software keys, viewport checks before/after Quick Settings, draft retention and both answers saved. Keyboard configured before launch; no mid-run intervention. | Physical IME, floating/split keyboards and broader multitasking/window layouts remain unverified. Earlier timeout retained as historical evidence. |
| Current iPad continuous voice | At 9b38dc90, test-9392df988b3e47dfb731e44535695d90: all three current correct-answer, unclear-kana retry and mistake-recovery journeys pass on iPad Pro 11-inch (M5), 60.260 seconds, zero failures/skips/runtime warnings. Fresh exported screenshot shows the centered subject, prompt, listening/fallback and study tools without clipping; normal simulator launch restored. Receipts: .build/Results/iPad-Voice-Current-20261025.log and iPad-Voice-Current-20261025/manifest.json. | Synthetic recognition; does not close the separate landscape keyboard-idle failure, live speech, multitasking layouts or physical-device acceptance. |
| Storage capture/publication | Base/WAL cross-volume copy ENOSPC and same-volume incomplete family capture recover 38 exact records in fresh processes. Final publication interrupted before fsync recovers 38 records, then an abrupt answer/note write recovers 39. Sources and abandoned preparations remain unchanged; detailed receipts are linked above. | Single-file mid-copy, APFS clone failure, iOS capture/publication and physical failures remain open. |
| Mainboard | Collector split regressions pass; compact report preserves numeric documentation URLs after a local formatter correction. | Both fixes remain in the unrelated pending reorganization; not committed/published as a coherent tool revision. |
| Live Mainboard app workflow | After the transient missing-module failure, live `app --help` and `app list` succeed, discovering three device targets and 28 suites. `mainboard app build usagiunagi --device mac --configuration Release --timeout 180` passes: build-4d0f913fffb445028c6c4ef5fbf678cd, zero reported compiler/analyzer issues. Logs: Mainboard-Live-Recheck-20261025.log, Mainboard-App-List-20261025.log, Mainboard-Live-App-Build-20261025.log. | Working checkout evidence, not a published Mainboard revision or hosted CI result. No app source change or new runtime acceptance inferred. |

Do not repeat passing checks without a relevant change. Record new evidence against
its source revision and link detailed receipts; update the requirement rows when a
remaining gate is actually closed. An evidence archive is not completion of the goal.
