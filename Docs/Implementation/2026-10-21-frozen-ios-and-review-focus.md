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

## Further adaptive controls and startup acceptance

Coverage's two menu filters previously occupied a fixed horizontal row. The same controls now use `ViewThatFits`: their natural width is tried horizontally, then they stack when it does not fit. Selection, identifiers and inline coverage details remain with the existing view. This uses neither an OS/size-class branch nor a platform utility; narrow screens, larger text and resized windows share the declaration. Compilation cannot prove the rendered layout or an open picker's behavior during resizing.

The next six-case selected-generation Mac diagnostic passes through the actual production opener: an exact 38-record control and five safe refusals for a missing metadata row, malformed metadata property list, missing model-version hashes, missing model-cache row and malformed model cache. Each negative mutation changes exactly one row with readback, rejects triggers, and preserves unrelated metadata fields/keys and the other metadata table. All errors are thrown and caught, with no framework signals. Original/retained/selector/generation membership and selected DB/WAL are unchanged; five cases change only SHM bookkeeping.

The missing row/hashes produce `invalidGeneration`; malformed metadata produces Cocoa error 259, missing cache a thrown Foundation `nilError`, and malformed cache Cocoa error 134060. These are observed errors, not inferred from failed SQL mutations. No production opener/schema fix was needed. First-adoption combinations and iOS corruption remain open. Existing child time/log/capacity limits apply; successful disposable images are removed only after assertions, while compact reports remain.

Direct metadata root: `native-upgrade-CC9AB0C7-4391-4252-B844-0AE2746BEABD`. Its typed `metadata-outcomes.plist` SHA is `3d07a65fc3aac1ac7cd2150dc02f72af4271ff6df0037e5b0ebb65154566c203`; `/private/tmp/usagi-g7-metadata-matrix.log` SHA is `108560556ba9b33ba2f1d819f98a4aae58d96a06ce75383857a95f2369b0107e`. The probe source SHA is `98235ffdf7f33e81a94ca76c5daabd845afb39e931b1cec1d3b95e8c3e6d0322`. The frozen fixture, V1 and production opener hashes are unchanged.

The existing root persistence task now has nine phases, adding this command after the independent 27-scenario payload matrix. All nine pass; `.build/Results/AdaptiveControlsPersistenceWorkflow.log` SHA is `bf4eec8598874b98db524320a3f43283db052c081e9837f48bc706ba7d1f1233`. The existing Actions lane also includes the metadata command with a 120-second bound. Root TOML and workflow YAML parse, with exactly one metadata phase. Mainboard's package pin/dependencies are unchanged; hosted Actions still requires authorized publication.

### Anki and locked input

The pinned original review controller includes Return while an Anki answer is revealed, opening assessment rather than automatically grading correct. The shared details controls had no Return/default-action entry even though native submit already supported assessment. The existing Anki menu now has that primary action and default shortcut. Its assessment dialog and disclosure reuse the same actions, including Incorrect, defer, exclusion and synonyms where available. Typed correction wording/behavior and direct Anki Correct/Incorrect remain intact. Katakana distinguishes initial reveal from later assessment rather than treating every submit as reveal.

The Japanese field's delegate previously interpreted every empty locked replacement as Backspace retry, including Cut. Its existing adapter now vetoes Cut only while the actual owner is locked. The first actual-field test preserved text/selection on Cut but exposed a separate failure: a direct system `deleteBackward()` changed locked text without reaching that delegate guard. The adapter now explicitly routes locked Backspace to the existing retry callback once and skips system deletion. The editable path remains `super.deleteBackward()`. The unchanged assertions now pass, including exact UTF-16 selection, no Cut retry, one Backspace retry, unchanged locked text and normal editable deletion. Tests touch no clipboard contents or normal account.

The earlier failed hosted result is retained as `test-39e7a2b808cf4bad924890ca6461a54e.xcresult`: 89/90 functions passed, build diagnostics clean, one real input assertion failed. Its tests report SHA is `ba5a39523fee56f1448736691eaf523dd52e457d699e1bb6e44c6187099910b8`; `AdaptiveControlsHosted.log` SHA is `2f88dd72230c7c8ae61a21f619e4e6ae67085e92ab62fc67dc0cc5e1fbabebdb`. Xcode also failed to collect simulator diagnostics after that assertion (`simctl` lookup); this is neither a compiler failure nor evidence for its cause. No global tool selection was changed.

The existing combined-Anki UI scenario now checks one-tap access to all five available actions, cancel without changing question/progress, then its original Incorrect→Correct completion. It compiles with the production view. **That UI scenario and actual Return/keyboard delivery have not run**. Source comparison, the non-UI field test and successful compilation do not establish rendered acceptance.

| Final follow-up check | Result / receipt |
| --- | --- |
| Hosted iPhone | 90 functions / 129 executions pass; no failures/skips/compiler or runtime warnings; `test-70e3ba7db4ae49baa29d71f6abff9f37.xcresult`; tests report SHA `b5377c3b8b8e2da7bb47ab75d661c5e6846c0b5c8b5056342da82aa7e1fcc64a` |
| Native Debug Mac build | Zero errors/warnings; `build-a226877d18674f298d59b7669bbb2254.xcresult`; report SHA `f5b12ecca8b46bac4e84a07c56ee77313cf1ae3159ba24bb68c20a675380ad72` |
| Shared Mac | 551 functions / 72 suites pass; `AdaptiveControlsSharedMac.log` SHA `c8410cc701f88f10fc8aacaca6eaf8720d4493ea1035ab7a606fbebade3c0818` |
| Parser inventory | 259/259 files parsed, zero gaps/context issues; `AdaptiveControlsInventory.json` SHA `d4c21b383491acbc6bbf0367835d4c009a3ee5e008be6ff47aaace8a4ca22a71` |

Final log hashes: hosted `06b3e5ba0a1459820eb7bd42f18e32a98c60a6dd1fb544d81609267bb5afa70a`; Mac build `e5aadac0c1cf8fe5d24cdf09f3403d610e535826977c675519dd7384b7e9f1ce`. Both generated hosted-test entries still use exactly `--review-fixture`. Root Mainboard strict formatting/SwiftLint/UI-parser checks pass all seven changed Swift files with zero rewrites; whitespace/project syntax checks pass. No GUI automation, real exercises, normal store, physical/signed services or new Release run was used.

Frozen source SHA values: Coverage `085e428221c578fb2ac3c1d384e06f69b7bbfd689b565e228ce55edb5afe1d96`; ReviewScreen `70236323a1aaafed9a8add383515322665d49d774281defe56edeacd5511d4aa`; Katakana `32581fe9265b8ad3a4c8ead9a8c6b7901051227826f04969c4bcbe2b53daa121`; input adapter `849ee5fb1460ae10199b3105b83005ce62c697ff7a0a01419d674a3726b9fca6`; input test `a5785d24199a05b082707703a03557fc7cc0bdd9d774e42adbb3d537381a39b9`; UI scenario `18590dd2731255e6083b151616d03f603020bf2f42544e57c42bf7fdf195aedb`.

This follow-up adds 30 production and 264 test physical lines: 145 production files / 21,536 lines; 109 test files / 24,291 lines; five tooling files / 281 lines. No deletion/LOC-saving claim is made for these adaptive and correctness fixes. Required input/service bridges, rendered/device acceptance, real-catalog performance and the broader G7 cases remain open.
