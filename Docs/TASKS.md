# Current modernization tasks

Updated October 25, 2026, at app `b0421e69`. **The modernization is not complete.**
Work in `/Users/pedro/Developer/projects/apps/usagiunagi`, branch
`codex/swiftui-27-curriculum`. Local commits only; no PRs, app pushes or distribution.
Only Mainboard publication through `fa467e07a71b26876f48b2dd3c273b5e3f14c1fd` is approved.

All prior evidence and source limits are preserved in the
[latest evidence archive](TASKS-HISTORY-20261025-afternoon.md),
[earlier October 25 archive](TASKS-HISTORY-20261025.md) and
[October 24 archive](TASKS-HISTORY-20261024.md). Historical “current” claims apply only
to their stated revision. This ledger tracks unresolved scope, not elapsed effort.

## Requirements and status

“Implemented” means source exists with the cited scoped evidence. It does not mean
all platform, physical-device or release acceptance is complete.

| Requirement | Implemented / verified scope | Remaining acceptance or decision |
| --- | --- | --- |
| One iPhone-first app | Shared SwiftUI root, account model and SwiftData store; adaptive tabs/sidebar, toolbars and forms. App-owned UI/services moved out of StudyUI/StudySpeech into App. Tests share App/Tests. | Wider iPad/Mac layouts, keyboard/IME, window restoration and original-app usability comparison. Preserve required bridges. |
| Lessons and reviews | Selection, interleaving, teaching, quizzes, Anki, correction, wrap-up, notes, synonyms, exclusion and summaries have scoped fixture acceptance. All 57 logged passes from the interrupted iPhone run now map to finalized receipts; five URL-driven journeys also pass. | Physical input/caret/IME, broader device layouts and final original-Tsurukame parity. Receipt reconciliation spans source revisions, not one full current-source suite. |
| WaniKani design | Pink/blue/purple subject colors, compact review/lesson flow, native typography, SF Symbols and glass controls; owner screenshots guide the design. Note-editor keyboard warning fixed on iPhone/iPad. | Full dark/light/high-contrast/Dynamic Type and VoiceOver coverage; broader iPad/Mac rendering. Two high-contrast voice journeys are accepted, not every screen. |
| SwiftData-only study storage | FMDB/importers retired. Native actor, outbox, frozen V1, generation validation/adoption and recovery. Mac/iPhone corruption, interrupted saves and bounded disk-full matrices have receipts. Mac base/WAL cross-volume copy and same-volume clone ENOSPC, partial-file/family interruption and final publication before fsync recover exact records. | iOS capture/publication (including partial-file interruption), physical pre-answer interruption, Data Protection/power loss and real-catalog/device performance. See storage invariants below. |
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

## Next work and acceptance gates

1. **Storage recovery:** finish iOS capture/publication boundaries (including
   partial-file interruption) using disposable stores and
   bounded experiments. The existing iOS interruptedOpening harness stops during
   container attachment, so it cannot prove these earlier/later boundaries. Preserve
   failed calibrations; do not repeat them unchanged. See the
   [probe guide](../App/Tests/PersistenceProbe/README.md), [migration spec](Migration.md)
   and [capture/publication receipt](Validation/2026-10-25-source-capture.md).
2. **Usability and accessibility:** compare populated lessons/reviews with the owner's
   original Tsurukame/WaniKani references; finish wider iPad/Mac layouts, window
   restoration, keyboard/IME and spoken VoiceOver/chart acceptance. Existing portrait
   lesson and landscape software-keyboard checks are scoped passes, not this full gate.
3. **Mainboard:** integrate the collector/report fixes with the concurrent reorganization;
   contextually triage remaining rule signals. Four report regressions preserve full
   documentation URLs, distinct targets and grouped values/counts. They depend on the
   pending implementation; do not commit them separately or stage unrelated edits.
   Live Mac build/audit works again. A coherent tool revision and newer publication
   remain pending; publication requires approval.
4. **Real data and devices:** account calibration, full-catalog performance and actual
   sync delivery remain unverified. Physical microphone, Watch/phone, iCloud/Keychain,
   notifications, signing and device performance are owner-deferred. Do not request
   setup again. Never perform real WaniKani exercises without authorization.
5. **Final reconciliation:** after remaining implementation/manual fixes, run the
   applicable final suites and Release/resource checks against the final revision.
   Hosted Actions has not run; an app push is not authorized. Do not substitute local
   pinned-manifest compatibility for a hosted run or signed distribution.

Keep UI runs and shared derived-data directories sequential and bounded. Do not rerun
passing scopes without a relevant change, failure or unresolved risk. Keep all receipts,
including failures. Do not suppress rules or remove functionality just to close a gate.

## Storage invariants

- Frozen `StudySchemaV1.swift` SHA-256 remains
  `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.
  Preserve original fixtures, writer archives and nested stored type identities.
- Failed adoption preserves original/retained data and abandoned preparations; retry
  chooses a fresh candidate. Grading penalties and exactly one pending answer survive.
- No V2 is required for the current app. Bind historical decoders into the actual
  upgrade path and close applicable G7 gates before a future schema/payload change.
  Further abstractions require measured benefit; no extra storage layer.
- Mac base/WAL capture ENOSPC, partial-file/family interruption and pre-fsync selector
  publication have scoped recovery evidence. The partial-file check kills inside the
  native copy after 1 MB of a 2.25 MB repaged disposable store; two fresh reopens
  preserve all 38 records and abandoned/source hashes. See the linked capture receipt.
  Same-volume native clone destination-collision recovery also passes for base/WAL
  stores: real POSIX 17 refusal, preserved collision/source bytes and two exact reopens.
  Bounded same-volume clone ENOSPC now also recovers base/WAL sources exactly twice,
  with native failure and direct WAL errno 28 evidence. iOS and physical power/
  Data Protection gates remain open.

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

## Current evidence pointers

| Scope | Source and receipt | Limit |
| --- | --- | --- |
| Mac Release through live Mainboard | App `82431eec`, build `33702d0a1bdb49f9b693b5f0243d4223`; `Live-Mainboard-Mac-20261025.log` and `Live-Mainboard-Mac-Bundle-20261025.log` | Build/bundle audit passes without fallback; no current UI/signing claim. |
| iOS Release and both resource audits | Production `c2c7e62c`, iOS build `9c5e2a1d099e4ae9a659f3af0882948a`; `Store-Parents-{Release,Bundle}-{iOS,Mac}-20261025.log` | Predates later lesson picker/settings changes. |
| iPad named lessons suite | Source `0d2b12cf`, test `da11e48086d34743ae035bb407b12324`, 5 passes; `Lessons-Named-iPad-20261025/manifest.json` | Normal/XXXL screenshots inspected; sparse fixture, portrait only. |
| iPhone lesson picker lifecycle | Test `397088e320f64ef19c3c748755e8b503`, 2 passes; `Lesson-Picker-Lifecycle-20261025.log` | No deterministic close-during-read race injection. |
| Statistics calendar | `c72d4704`, test `5942be029cac4d6695c8a481e735502c`, 12 functions/13 cases | Includes both DST transitions; no real-account calibration claim. |
| Subject settings simplification | `82431eec`, test `23dd9107e33544d6973e38a03810aabd`, 6 passes | Local merge/reopen, not physical iCloud delivery. |
| Shared logic/storage | Source `c2c7e62c`, 197 core + 172 persistence functions; `Store-Parents-Full-Shared-20261025.log` | Scoped source, not all app/UI tests. |
| Repository enforcement | Source `f5e27dde`, full lint 449 files; rules 240 findings | Later focused lint passes do not replace final full enforcement. |

Receipt paths are relative to `.build/Results/`. Voice, native Mac interaction,
keyboard, CI-pin compatibility and earlier storage details remain in the linked
archives with their exact source scopes. Update requirement rows only when their
acceptance gate is actually closed; an archive or passing subset is not completion.
