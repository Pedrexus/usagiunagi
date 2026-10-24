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
| Mainboard rules/workflow | Swift rules, formatter/SwiftLint, inventories, native builds/results and 28 named app suites. Optional pytest collection is isolated; two regressions pass. Installed CLI/build/launch work after the dispatcher repair; compact-report documentation links are corrected locally. | October 25 inventory reported 239 signals; 77 Swift migration signals have contextual review. Continue general-finding triage. Collector/report fixes remain within the pending reorganization; integrate without staging others' edits. Newer publication needs approval. |
| GitHub Actions / final tests | Bounded native lanes, pinned packages, storage matrices and product audits declared. All five tool checkouts pin published fa467e0. Local app/rules commands are newer than that pin. | Hosted run not performed: app push is not authorized. Newer Mainboard publication also needs approval. Tests run after implementation/manual repairs; preserve full assertion scope. |
| Launch/reopen reports | iPhone native root, warm links, held refresh, account flows and normal simulator launch have finalized receipts. One pasted crash was SpringBoard, not the app. | Current broader Mac/window restoration and any newly reproduced matching app crash. Latest Mac UI attempt failed to connect its runner before executing tests. Do not equate compilation with launch acceptance. |

## Remaining work

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
| Grading and storage | 0f6213a1: 196 core + 171 persistence test functions pass. 6da3570a: 13 review-store functions pass, including three alternate-kana cases preserving retries/outbox. | Shared logic, not physical recognition or signed transport. |
| Automatic sync account fences | After three awaited account-state reads, the worker now checks account identity before applying refresh state, notices or retry scheduling. All 18 `AutomaticSyncTests` pass on iPhone 18 Pro / iOS 27, including disconnect during read/write, offline recovery, uncertain writes, throttling and scene ownership. Receipt: test-c8106b43bef043adbbbd04ec0703c098; logs: AutomaticSync-AccountFence-20261025.log and AutomaticSync-AccountFence-Lint-20261025.log. | Existing regression suite and source-level suspension-boundary audit; no deterministic interruption inside those three database reads, real-account or physical transport claim. Release integration is covered by the current products row. |
| Current Release products | At dc6508d8: iOS build-25571d7174e944da8e516c77ef5b80aa; Mac build-9971ecb80a5e4a968e860d9e194a98c1. Both report zero compiler/analyzer issues. Both declared bundle audits pass with no violations: localized names, icon metadata, microphone description, forbidden retired symbols and frozen/test resources. Receipts: Lesson-Controls-Release-{iOS,Mac}-20261025.log and Lesson-Controls-Bundle-{iOS,Mac}-20261025.log. | Compilation and declared bundle constraints only; no signed distribution, physical icon appearance or full runtime claim. |
| Repository enforcement | Kana-Final-Lint-20261025.log: 448 files, no rewrites/failures. | Informational review signals are not suppressed or all treated as defects. |
| iPhone layout | test-22ced2841c594fb99ba6ef315844195f: catalog paging/hidden answers/stages and inline pace comparison pass; fresh screenshots inspected. | Before the grader fix; same catalog/chart layout. |
| iPhone continuous voice | At 09276bee (production grader 0f6213a1): test-52368b7149b04c70a182887a4443ea0b passes all three journeys: both answers without taps, unclear-kana retry without grading, and mistake recovery without taps. Fresh inline-reading screenshot inspected; normal simulator app restored. Receipts: .build/Results/iPhone-Voice-Kana-20261025.log and iPhone-Voice-Kana-20261025/manifest.json. | Fixture recognizer; no live microphone or physical-device claim. Screenshot confirms subject color, reading strip and inline listening/keyboard controls, not full original-app parity. |
| Mac continuous voice | Debug build-d133fa1d8a52471d979d922e7ca54396 with current grader: three isolated native journeys required only starting reviews and enabling voice. Correct answers reached 100% / 1 of 1; unclear kana showed correction with submission disabled, retried and reached 100% / 1 of 1; a wrong meaning showed the expected answer, continued automatically and retained 0 of 1 in the saved summary. Bounded native observation logs: .build/Results/Mac-Voice-{Current,Repeat,Mistake}-*-20261025.log; exact observer and inspected mistake-summary screenshot retained. Fixtures exited; normal Release app focused. | Synthetic recognition, not live speech, physical transport or XCTest runner acceptance. Read-only observation after activation introduced no answer/advance actions. |
| Mac layout/navigation | Native isolated Debug build-d133fa1d8a52471d979d922e7ca54396: stats, inline pace, six settings/media routes inspected. Native chart labels and AXValueDescription verified. | Default light appearance; no VoiceOver speech, setting writes, downloads or playback. Normal account launch/preview/reopen has separate earlier evidence. |
| Current Mac startup | Release build-ee89e3a3bad94084aaaaae9ea1b5dae0: terminated the old running process, launched PID 70875 to Account, opened the display-only catalog, verified graceful exit, and reopened PID 71677 to Account. Native accessibility inspection found responsive controls and one window on both launches. Dark catalog screenshot inspected. Receipts: .build/Results/Mac-Current-Reopen-*-20261025.log and Mac-Current-Reopen-Preview-20261025.png. | No token entered or exercises performed; signed-account and session/window restoration are not proven. Preview is not restored automatically on relaunch. |
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
