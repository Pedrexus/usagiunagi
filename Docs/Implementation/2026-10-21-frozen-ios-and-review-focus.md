# iPhone adoption and review focus

The main priority remains one iPhone-first SwiftUI experience. Native tab/sidebar adaptation, semantic toolbars, search, forms, available space and Dynamic Type adapt the same screens to iPad and Mac. The remaining shared-UI OS checks configure APIs rather than separate layouts. This checkpoint adds no platform utility or persistence layer.

## Previous-subject return

The pinned original review controller restores typing focus when its screen returns. The shared native review view already restores focus after Settings and Voice, but lacked that path after Previous subject. It now restores the existing answer focus when the subject destination closes during an active typed question. It does not reload the session, replace the input subtree or alter the draft.

The new `testPreviousSubjectReturnRestoresTypingFocusAndPreservesDraft` completes one isolated fixture subject, enters a draft on the remaining question, visits Previous and returns. It then types through the application without tapping the field and requires the exact appended draft, question, prompt and progress. The scenario compiles in the iPhone build. **Its UI interaction has not run**; no GUI access or automation workaround was used. Source comparison is not rendered acceptance.

## Frozen store on iPhone

`FrozenNativeStoreTests` reuses the existing baseline source and pinned fixture directly in `AppTests`; neither is duplicated or shipped as an app resource. The test target's Debug configuration now inherits `DEBUG`, matching the existing baseline helper's compilation condition. The first build failed because that condition was missing; `FrozenStoreAdoptioniOS.log` is retained rather than counted as a test run. The corrected focused run is `FrozenStoreAdoptioniOS-Debug.log`.

The actual production opener passes on the iPhone 18 Pro / iOS 27 simulator. The test checks both pinned SHA-256 values before persistence access and compares all 38 records and fields against the frozen manifest, covering ten model types and two accounts. It requires a selected generation and byte-exact original/retained images. After releasing the actor it reopens, saves a revision-checked note containing a newline, NUL and supplementary character, verifies the other records remain exact, releases and reopens again, and compares the complete edited state. Selection, original, retained and bundled fixture bytes remain unchanged.

This is simulator adoption and repeated **same-process** actor reopening. Fresh-process iOS/WAL-only adoption, physical file protection, signing, mid-copy interruption, disk-full and power loss remain open. It does not establish a V2 upgrade or independently freeze historical nested decoders. The V1 schema and production generation opener are unchanged by this checkpoint.

## Selected-store corruption matrix

The existing Mac-only disposable probe now runs a fixed 27-scenario matrix: two truncated payloads, a wrong-typed required JSON field in each of the fifteen Codable paths, nine required SQL NULL mutations, and a valid populated `ReviewRecord.issue` control. The control borrows a valid material issue and changes only that expected field before comparing all 38 records. Each negative mutation changes exactly one row and must survive exact readback; the wrong-typed cases keep valid JSON and all unrelated fields unchanged.

All **26 actual production-opener negative cases** refuse through caught `invalidGeneration`, exit 74, without a signal or returned owner. All nine NULL mutations were exercised; zero were rejected by SQLite constraints. The valid control exits 0 with exact state. An SQL constraint rejection would be reported as unexercised, not as an opener-refusal pass.

The probe now requires preservation of the selected DB/WAL as well as original, retained, selector and generation membership. Only selected SHM bookkeeping may change. The fixture is capped at 16 MiB, free space must exceed 512 MiB, children have 10-second/1-MiB bounds and the direct matrix has a separate 120-second deadline. Only successful marked case copies are removed after assertions; logs/outcomes and failed images remain. Raw SQL belongs solely to the disposable corruption diagnostic, not the application writer.

The first expanded attempt refused its own selected path because URL equality treated a directory representation differently. It exited 251 before a negative mutation/opener case. Canonical path comparison fixes the harness defect; the failed log/image remain. This failure is not a production payload finding.

The final direct matrix root is `native-upgrade-67639215-54FB-4E1D-B5DF-C14708B11217`; log `/private/tmp/usagi-g7-expanded-payload-matrix2.log`. The root eight-phase persistence workflow also passes with the expanded command, including base/WAL adoption, lease refusal, abrupt answer/note commits and fresh-process Mac reopens. Malformed metadata/model caches, first-adoption corruption combinations and real-catalog startup cost remain separate acceptance work.

The direct structured `payload-outcomes.plist` SHA is `17ae19f53ad3df298cff66d9a766d06c40c9bab979190b4841ddaa4fd0125828`; success log SHA is `cbd13bf35d48569ad95726f6c233155623bf5d2b39b16ffd5efeccc326c6bf1e`. The earlier harness-failure log SHA is `fa7c07fa6e03036219ec7f3da93b23457673dec639115209c58d08fd8eaee67e`, with its image retained at `native-upgrade-53043277-1D0C-4D06-BDC9-610456544005` under the same temporary parent.

## Receipts

| Check | Result / receipt |
| --- | --- |
| Focused frozen iPhone | One test passes; `test-9035e942563f4520af12f56f81b7055c.xcresult`; tests report SHA `b74af8b8c5814ceac135ecf1944590e924b860e58751ee9fd9762b5fe03e8eca` |
| Full hosted iPhone | 89 functions / 128 executions, zero failures/skips/compiler or runtime warnings; `test-85480a77c827474eb38bfa9db04a2e47.xcresult`; tests report SHA `89edc302c33e56b2423d85cf305ebb9b1cd3e5345ab66424e100ea0c1d15adaf` |
| Shared Mac | 551 functions / 72 suites pass; `FrozenFocusSharedMac.log` SHA `95e6eaf56881f91b391dcaaa65420205b6c28433d591036e31ed702869abf87b` |
| Root persistence workflow | Eight phases pass; `FrozenFocusPersistenceWorkflow.log` SHA `8038ef409aef72f1209e6907d00a01c6c01f42c902f620893e2aaea93bc4cf8d` |
| Final Swift inventory | 259 files parsed, zero gaps/context issues; `FrozenFocusInventory-Final.json` SHA `c9d4e20cd288080bc0f232207eab2e3ce70c46be964fd675520e6d00941c206a` |

Logs and native results are retained under `.build/Results`; inventory is under `.build/Reports`. Hosted-test launch configurations retain exactly `--review-fixture`. No normal account, live WaniKani exercise, UI-test runtime or signed service was used. Prior Release builds and shared iPhone results remain historical at their recorded sources, not new runs for this checkpoint.

Root Mainboard's scoped Swift formatter, SwiftLint and UI/parser checks pass for all four changed Swift files with zero rewrites. Project property-list syntax and whitespace checks pass. The three protected owner edits remain outside this commit.

Source SHA-256 values: review view `eb541ace45c27c5c518ad2761031bdcdcc7c273925d04e1c2687260078ac90f6`; UI scenario `3ac5168145d2f30056d6f8091348da3aca26da176a4fbebd78ed6c19c5d0d59c`; frozen test `1ab662a6fce51b81329a222a668712ed83f9c779c19b4e663c9bf741284c3a1d`; expanded probe `7739d84905be227010f9d1f7ba9d616538f6c66428b4aa497387b2272a8abc41`.

Inventory classifications are 145 production files / 21,506 physical lines, 109 test files / 24,027 lines and five tooling files / 281 lines. This checkpoint adds six production lines and 475 test lines; it is a correctness/acceptance change, not a LOC reduction. Classification and parser coverage do not establish target membership or safe deletion. Mainboard remains at `7776240`; no new tool framework or dependency is needed.
