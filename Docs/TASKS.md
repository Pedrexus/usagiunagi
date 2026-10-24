# Current modernization tasks

Updated October 25, 2026. **The modernization is not complete.** This is the current
decision and work ledger; [the complete October 24 ledger](TASKS-HISTORY-20261024.md)
preserves all earlier receipts, failed experiments, comparisons and source scopes.
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
| SwiftData-only study storage | FMDB/importers retired. Native actor, outbox, frozen V1, generation validation/adoption and recovery. Mac/iPhone corruption, interrupted saves and bounded disk-full matrices have receipts. | Earlier source-copy failure, abrupt mid-copy/inside-publication interruption, physical pre-answer interruption, Data Protection/power loss, real-catalog/device performance. See storage invariants below. |
| Offline sync and recent mistakes | Durable pending work, account/origin fences, rollback/retry, refresh cancellation and 24-hour mistake projection have scoped tests. | Real account permissions/delivery, signed iOS/Mac KVS identity, multi-device/account transitions and offline recovery with real data. Never perform live exercises without authorization. |
| Continuous bilingual voice | English/Japanese selection, pause-to-submit, automatic advance/mistake/retry and keyboard fallback. Kana script is preserved; recognizer alternatives can disambiguate without an answer key. Actual Mac file-fed capture/controller works. | Live microphones, language-model readiness, latency, interruptions/audio routes and human recognition across physical iPhone/iPad/Mac. Synthetic capture and generated audio are not live speech acceptance. |
| Watch reviews and widgets | SwiftUI Watch app, foreground voice loop, phone recognition/grading bridge, four WidgetKit families and atomic snapshot. ClockKit migration code removed. | Physical paired Watch/phone transport, permissions, reachability, locked/background phone behavior, signed App Groups and installed-face/cache upgrades. |
| Credible statistics | Swift Charts, focus prioritization, held-out pace comparisons, school/Jōyō/estimated JLPT and verified Kanken memberships. Pending subjects separated. Explicit chart accessibility values added. | Full-account calibration, real-catalog performance and spoken chart acceptance. Character coverage and pace are not exam-pass predictions. |
| API/cache/mock data | WaniKani API to SwiftData; subject deltas merge safely; other endpoints use complete downloads. Parquet/export tooling retired. 357-item levels 1–3 preview is display-only. | Permitted real-account/offline verification and measurements. Conditional HTTP requests remain optional measured work, not a required new cache layer. |
| Settings and private iCloud | One page groups six WaniKani controls and app preferences; debounced account-fenced updates. Independent private SwiftData schema covers 46 portable choices with per-field reconciliation and study deferral. | Owner container registration, signed entitlements, cross-device/background/account-change delivery and real WaniKani permissions. Device-specific choices stay local. |
| Native media/services | Shared settings, fonts/audio, diagnostics, notification preferences and background scheduling with scoped iPhone/iPad/Mac evidence. | Remaining Mac media/settings equivalence and physical notification/background/audio behavior; signed Keychain continuity. |
| Rename/icon/localization | Fork remote is Pedrexus/usagiunagi. Localized 兔鰻/usagiunagi names and shared layered kanji icon compile; earlier bundle/static exports checked. | Physical Home Screen/Dock/Watch appearance variants and signed identity acceptance. Store listings/distribution require separate owner authorization. |
| Lean code and modern Swift | Retired UIKit screens, Go/Objective-C/FMDB/protobuf/importers/assets removed; redundant app initializers reduced. Shared modules remain where persisted identity requires them. | Continue only evidence-based simplification without losing functionality or frozen data. Resource and final Release acceptance remain scoped. |
| dataclass / constructor helpers | Separate reusable library and SwiftData/macro tests implemented. App pilot saved only three lines, so native constructors retained. Weak lifetime boundaries audited. | Publication and a larger measured benefit before app adoption; physical-service lifetime checks. No frozen-schema changes for boilerplate savings. |
| Mainboard rules/workflow | Swift rules, formatter/SwiftLint, inventories, native builds/results and 28 named app suites. Optional pytest collection is isolated; two regressions pass. Current installed CLI, warning-free iPhone build and simulator launch pass after the dispatcher repair. | Current rules report 238 signals, including 77 Swift migration signals; review remaining general findings individually. Collector fix remains uncommitted alongside other work; integrate without staging others' edits. Newer publication needs approval. |
| GitHub Actions / final tests | Bounded native lanes, pinned packages, storage matrices and product audits declared. All five tool checkouts pin published fa467e0. Local app/rules commands are newer than that pin. | Hosted run not performed: app push is not authorized. Newer Mainboard publication also needs approval. Tests run after implementation/manual repairs; preserve full assertion scope. |
| Launch/reopen reports | iPhone native root, warm links, held refresh, account flows and normal simulator launch have finalized receipts. One pasted crash was SpringBoard, not the app. | Current broader Mac/window restoration and any newly reproduced matching app crash. Latest Mac UI attempt failed to connect its runner before executing tests. Do not equate compilation with launch acceptance. |

## Remaining work

1. Integrate the verified local Mainboard collector fix into its pending tool work.
   The dispatcher syntax failure is now repaired in the current checkout: normal
   app build and simulator launch pass. Triage the current 239 rule signals without
   deleting required bridges or frozen evidence. Preserve unrelated in-progress
   changes and do not publish newer tooling without approval.
2. Finish supported local storage failure boundaries using marked disposable stores
   and bounded volumes. Avoid repeating rejected calibrations recorded below.
3. Finish adaptive layout, original-app comparison and keyboard/IME/accessibility
   acceptance. Fix demonstrated regressions before rerunning affected checks.
   Do not retry unchanged Mac runner or Device Hub hangs indefinitely.
4. Obtain physical/signed/account prerequisites for voice, Watch, iCloud, Keychain,
   notifications, real-catalog performance and statistical calibration. These remain
   incomplete until actually exercised; local mocks cannot close them.
5. Reconcile final source-specific checks and Release/resource/icon evidence after
   changes. Hosted CI and distribution are gated by separate publication authorization.

Keep checks bounded and serialize UI runs and shared derived-data directories.
Re-run accepted scopes only for a relevant source change, failure or unresolved risk.

## Storage invariants

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
  preserving sources and failed preparations. Same-volume cloning, nonzero mid-copy
  interruption and iOS capture remain unverified. See the
  [scoped receipt](Validation/2026-10-25-source-capture.md).

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

Detailed receipts and earlier implementation history remain in the
[unchanged archived ledger](TASKS-HISTORY-20261024.md). Local `.build/Results` evidence
is intentionally untracked and must not be deleted as disposable build output.

| Commit / receipt | Scope |
| --- | --- |
| `test-0e6278df4ce5404da8fc3bd2a38d47d2` | Removed the fixed blue foreground from the noninteractive synonyms row; native LabeledContent now distinguishes its label/value and avoids implying a link. Existing dark lesson journey passes; fresh `Lesson-Synonym-Style-20261025/9C029F95-D154-45C2-B0E1-27D75512D783.png` inspected. Editing remains on the existing edit button; no synonym data/grading change. |
| `test-21a3d17f6e454d1bb3b6013bd06e1f94`, `Mnemonic-Color-Resolution-20261025.log` | Fixed mnemonic foreground contrast in dark appearance with native SwiftUI Color mixing; light appearance and colored tile fills stay unchanged. Resolved colors measure approximately 6.3–6.8:1 against the sampled #1c1c1e surface. One dark iPhone lesson journey passes; fresh screenshot inspected for readable kanji mnemonic emphasis and unchanged subject tiles. No claim of full accessibility audit: other blue controls/text, all surfaces, enlarged text and VoiceOver still need acceptance. |
| `test-7b95ca573c044f6ab14c824114926045` | New iPhone statistics journey confirms the eight-level range explanation, five-level past-error summary and inline disclosure chart, with no sheet. One pass, zero skips/runtime warnings and zero structured build warnings. Fresh screenshot `Pace-iPhone-20261025/2F42D8CC-95C3-4879-BDE4-03FAAECDAE33.png` inspected: explanation, forecast caveats, chart and note readable without clipping. Fixture values only; not real-account calibration, all forecast-suppression branches, dark/large-text or spoken VoiceOver acceptance. |
| October 25 original-control source recheck | Compared local original `master` at `d20defc3` with lesson/review controls at `107c4e9f`; mappings and the narrower Anki tap behavior are recorded in the original-flow document. Corrected Architecture's stale claim that the removed SQL importer still runs. Source mapping does not close rendered/physical keyboard parity. |
| `build-be7074cfad6c43e8aea6510336b03770`, `iOS-Release-Bundle-20261025.json` | Current generic iOS simulator Release build succeeds with ad-hoc signing. Bundle policy passes across three packaged binaries (app, Watch app, Watch widgets), 37 files: localized names/icon metadata, microphone text and excluded test/retired-library patterns. Structured diagnostics report zero warnings, but raw output contains an App Intents metadata-extraction warning for the app's absent AppIntents dependency; do not describe this run as warning-free. No physical installation, distribution, runtime Watch or signed-service claim. |
| `build-0496a8548ee14fb5a2c0197c7b73d65c`, `Mac-Release-Bundle-20261025.json` | Current native macOS arm64 Release build at `212aa151` succeeds with zero errors/warnings. Mainboard bundle audit passes with no violations: default/localized usagiunagi/兔鰻 names, UsagiUnagi icon metadata, microphone usage text, forbidden fixture/test resources and retired FMDB/Hippolyte/PromiseKit symbol patterns. One packaged binary inspected. This is unsigned compilation/packaging evidence, not launch, rendered icon, live voice or signed-service acceptance; no distribution performed. |
| `build-045273e855b842dcadff90ca6a5009a2` | Level pace now states its middle-half historical range and sample count, and explains missing date estimates for pending answers, vacation, level 60 or absent/currently unsuitable dates. Calculation and grading are unchanged. iPhone build reports zero errors/warnings; strict formatting passes. This does not establish real-account calibration or spoken/visual acceptance of the added text. |
| `build-068c10dd5d67462982e58ca2db9685b4`, `test-d6822618bff84bc0a81c2690228c62c1` | Removed unused review focus action and never-assigned image state; radicals still use the live question-content loader. Merged identical advance branches. Strict formatting and warning-free iPhone build pass. One iPad continuous voice journey passes without further taps after starting, zero skips/runtime warnings; fresh exported screenshot shows readable prompt/listening/fallback/tools without clipping. Synthetic recognition only. Earlier attempt `test-b758aaf03baf4fd9a5b17a90a3054e66` selected the wrong test target and executed zero tests; corrected target produced the accepted receipt. |
| `Preference-Cleanup-20261025.log`, `Cleanup-Findings-20261025.log` | Reviewed duplication/complexity findings; independent frozen-store expectations remain independent. WaniKani partial settings use native memberwise construction and nil coalescing instead of 12 conditional bindings, without a helper abstraction or storage-format change. One Swift Testing function with two cases passes for explicit false/true, accumulated edits, empty edits and unknown server order preservation; strict formatting passes. This is local value behavior, not live settings synchronization acceptance. |
| `build-47d5dd39fb9f4a558b54852b8d4c66e0`, `Mainboard-Current-Launch-20261025.log` | Current installed Mainboard (no snapshot override) builds iPhone with zero errors/warnings and launches bundle `com.davidsansome.wanikani`, PID 85282. This verifies workflow recovery, not manual usability or physical-device behavior. |
| `Mainboard-Current-Rules-20261025.log`, `Mainboard-Current-Swift-Rules-20261025.log` | 238 signals across 14 rules; 77 Swift migration signals across eight rules. UIKit/Objective-C signals identify the Japanese input bridge, notification adapter and tests; SQLite signals are confined to disposable persistence tests/probes. Frozen V1 Codable storage and intentional container boundaries also signal. Findings are not automatically bugs or safe deletions. Remaining general complexity/duplication findings require individual review. |
| `Storage-Encoder-20261025.log`, `Storage-Encoder-Frozen-20261025.log` | Reuse one local sorted-key JSON encoder per synchronous generation snapshot instead of one per field. All seven opening test functions and the frozen base/WAL/review/publication process matrix pass; source/retained checks and the schema hash remain unchanged. Strict Swift formatting passes. No startup latency or physical-device performance claim. |
| `Mainboard-Collector-20261025/{target,outcomes}.json` | OS-isolated regressions: CLI help with pytest blocked, and parameterized collection without execution; two passes/no skips. Default CLI discovery/toolchain and app Swift lint also pass. No dependencies installed. Mainboard source changes remain local/uncommitted. |
| `bcd524f8`, `test-ff6d4179c2df47bf815e347d179b18f1` | Two hands-free iPhone flows with Increased Contrast; screenshot inspected; original setting and normal launch restored. |
| `1e66d190`, `build-0b11948bb45340e29102735b697d08bc` | Explicit statistics chart accessibility values; scoped lint and warning-free iPhone build. Spoken VoiceOver unverified. |
| `3e77fed7`, `build-9c68d7c8ceab4fdab0538d4cd2b84e24` | Local app manifest and corrected workflow guide; build/lint/launch. Later installed-CLI dependency failure supersedes default-command usability. |
| `de08be10`, `Capture-Limit-Recovery-20261024.log` | Verification-file-limit failure recovery; original/retained bytes and failed preparations unchanged. Not capture failure. |
| `98bb7207`, `test-fc65d99d25d9473e8a1f9117a9e1f8d7`, `test-3ed7bc7855434cec9c5f53c5b033a844` | Warm links and held-refresh iPhone journeys. |
| `b2620ecf`, `test-820fa296ecbf40739818d5401cf18a22` | Three driven note-conflict cases after editor fix. |
| `dd472e54`, `test-d8814d06c8344e6387069634a05fb915`, `test-2fcf13d933274f47a92125c8dea96a7a` | Note keyboard Done action and warning-free iPhone/iPad flows. |
| `iPhone-Broad-Pass-Reconciliation-20261024.json` | All 57 earlier logged passes mapped to finalized receipts; mixed source revisions. |

Completion requires evidence for every remaining requirement above. Do not close the
goal because builds pass or because all currently runnable synthetic checks pass.

### October 25 iPad large-text follow-up

- Fixed the UI test scroll helper to anchor its drag inside a visible content row;
  the collection frame includes the sidebar on iPad. No app behavior or assertions
  changed. Initial failures are retained in `test-f8fa08b91e674ef4bf8e9a190fb241aa`.
- `test-d644b489b1ad495d96b806789b85375b`: both Home action/progress reachability
  and lesson heading/footer checks pass at the largest Dynamic Type size.
- `test-107f056a4bff4dcd84872960b07301e9`: lesson recheck passes using a direct
  window screenshot instead of the application capture. The exported image
  `iPad-Lesson-Window-20261025/298C846D-2B39-41A5-BDBC-EA6665F02385.png`
  shows the full heading and quiz controls without the earlier capture's black
  band/cropping. Heading height increases from 57.5 to 86 points. These are scoped
  simulator fixture checks, not VoiceOver, physical-device or complete UI acceptance.

### October 25 subject-details simplification and iPad review checks

- SubjectDetailsContent now uses Swift's synthesized memberwise initializer within
  the app module. Removed the unused custom sentence-rendering callback; all callers
  already use the retained vocabulary highlighter. Net reduction: 27 source lines.
  Answer-visibility policy remains computed from the same question set. Catalog and
  material-editor constructors still initialize/clamp state and are not equivalent
  boilerplate. No schema, sync or grading changes.
- `test-ae14eb7ea21d49c1b4c6cff87c84e3e3`: two iPhone journeys pass on the simplified
  source, checking hidden unanswered reading/editor fields, explicit full-detail
  reveal, translation reveal and dark lesson mnemonics. Zero structured warnings,
  runtime warnings or skips. Exported sentence screenshot inspected; highlighting
  and translation remain present. Strict Swift formatting passes.
- `test-21c16f568cf5493ba0888e1862ed6352` (before that source edit): iPad Quick Settings
  preserves the draft, rejects a typo with exact match enabled, then accepts it when
  disabled and completes the kana reading. One pass, one failure: landscape viewport
  acceptance requires a visible software keyboard, but its recorded frame is
  `(0, 834, 1210, 0)`. Screenshot shows visible controls with the keyboard hidden.
  Do not weaken the assertion or claim above-keyboard acceptance; rerun after the
  simulator keyboard configuration is corrected. No physical checks are required
  to close this simulator-specific gap.
- Current Mainboard root rules check completes: 239 signals across 14 rules,
  including the unchanged 77 Swift migration signals. Raw reports are
  `Subject-Details-Rules-Final-20261025.log` and the initial unsupported single-file
  invocation in `Subject-Details-Rules-20261025.log` (NotADirectoryError).
  A rule signal is not itself a demonstrated defect; required boundaries and
  independent test expectations remain intact. Normal iPhone launch restored.
