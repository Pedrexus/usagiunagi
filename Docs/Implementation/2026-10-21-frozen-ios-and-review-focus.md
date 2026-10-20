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

## Voice assets, shared correction input and first-adoption retries

The iPhone-first priority remains the organizing rule: one study flow, native semantic toolbar/search/form behavior, and adaptation from offered space and Dynamic Type. An audit of the active shared UI found no device-idiom or size-class layout forks. Remaining OS conditions configure actual keyboard, audio, notification, system Settings and activity APIs; the app scene also configures unavailable background/window APIs. They stay beside those boundaries. This follow-up reuses the existing review field for voice correction rather than introducing a generic platform helper or another input implementation. Rendered phone, tablet, window resizing, largest text and keyboard behavior remain open because computer access is unavailable; no GUI workaround was attempted.

### Real file-fed speech and asset readiness

Apple's [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) accepts [file audio and can finish its result streams at EOF](https://developer.apple.com/documentation/speech/speechanalyzer/start(inputaudiofile:finishafterfile:)). Apple's [asset installation request](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)) returns nil when no installation is required; obtaining the request reserves its locales, while `downloadAndInstall()` performs the installation. The installed Xcode 27 / Swift 6.4 public SDK interface agrees. Third-party search results were not used as API evidence.

Public API diagnostics initially reported both en-US and ja-JP as supported but not installed. Resolving the English installation request returned nil and then reported installed. Japanese returned a request, whose installation completed in 9.626 seconds; no network byte count was measured, so this is not proof of a fresh network download. In a later fresh process both initial statuses again reported supported, yet the requests were nil and real analysis succeeded. `AppleVoiceCapture` now uses that optional request to decide whether the explicit Download action is necessary. It still refuses unsupported languages, checks cancellation after suspension, and performs an actual installation only after the existing explicit download action. The previous status-only decision could show Download despite ready assets. No new service abstraction or permission policy was added.

Two short local AIFF files were synthesized with system `say -o`, using the observed Samantha English and Kyoko Japanese voices, without speaker playback. The bounded diagnostic uses `SpeechTranscriber` and `SpeechAnalyzer.start(inputAudioFile:finishAfterFile:)`, accepts only those two canonical temporary paths, and caps input at 15 seconds/16 MiB. All compilation/invocation went through root Mainboard with explicit Xcode selection. No microphone, speech authorization prompt, account data or exercise was used.

| Local synthetic input | Duration | Actual final result | File-analysis elapsed |
| --- | --- | --- | --- |
| “one thing”, en-US | 0.850 s | `One thing.` | 0.347 s |
| `ひとつ`, ja-JP | 0.708 s | `1つ` | 0.272 s |

Both runs exit 0 with one final segment and empty error logs. These are real file-fed recognizer results, not simulated capture results. Two clean synthetic clips establish neither human recognition accuracy nor live microphone/capture-sequence behavior, end-to-end latency, pronunciation assessment, iOS readiness, interruption or route handling. The Japanese digit output reinforces the existing non-kana guard; the app does not infer a pronunciation or grade automatically.

The first English diagnostic failed its own canonical path guard (`/private/tmp` versus `/tmp`) before analysis. An uncaught top-level diagnostic error produced a Swift fatal exit 251; it was not an engine/language failure. Canonical comparison and a caught normal exit 74 fix that harness behavior. The failed empty JSON and error log remain in `/private/tmp`; no failing production capture was hidden.

`VoiceAnswerPanel` now uses the existing `StudyAnswerInput` only for reading corrections. iPhone receives its existing romaji/Japanese keyboard handling; Mac keeps its native IME. English retains its multiline field. The input accepts the existing `voice.transcript` identifier, with `review.answer` still the default. Recognized text remains untouched until an actual edit. Return dismisses correction focus without checking the answer, and leaving the reviewing phase clears focus intent. These are shared declarations with no new OS layout branch.

The new hosted non-UI test drives the actual UIKit delegate/coordinator binding from raw `1つ`, through explicit `hitotsu` replacement, to `ひとつ` with UTF-16 caret position 3. It verifies the raw text starts blocked, kana becomes submit-eligible and focus intent stays false. It does not exercise a rendered SwiftUI sheet or hardware keyboard. The existing shared controller test is parameterized for both kanji (`一。`) and numeric (`1つ`) transcripts: neither can submit before explicit kana correction. Normal grading, question identity checks, submit/cancel and audio ownership remain unchanged.

### First-adoption refusal and repeated reopening

The existing disposable driver adds a separate `probe-application-adoption-corruption` command; the 27 selected-payload and six selected-metadata scenarios retain their counts. Before any production open, the new fixed matrix checks an intact source, a truncated required account payload, a deleted model-cache row and a malformed metadata property list. Each runs in two fresh child processes. Unselected mutation is restricted to a marked regular, nonsymlink `study.store` whose directory contains only the original store family. Each damage changes exactly one row with readback.

All eight attempts pass: the control preserves all 38 records and exits 0 twice; each damaged input is caught and exits 74 twice without a signal or returned owner. Negative selection remains preparing, never selected. Retry retains the same retained image, uses a new candidate and preserves every prior file/directory, including empty abandoned preparation folders. Source and retained bytes stay exact. The negative retries add 11, 11 and seven new artifact paths respectively; only the preparing selector may change among existing paths. The selected control preserves selection/DB/WAL, allowing only SHM bookkeeping; its second observed attempt adds/changes no paths.

Artifact snapshots are capped at 512 paths/32 MiB, source at 16 MiB, free space at a 512-MiB minimum, children at ten seconds/1 MiB, and the direct matrix at 120 seconds. Successful marked images are removed only after all eight assertions pass; compact typed outcomes/logs remain and failure images are retained. The first harness attempt stopped before any child because enumerated `/private/var` URLs were compared against a `/var` parent. Canonical parent comparison fixes that harness defect; its failed image `native-upgrade-D29BC60F-3EAD-4ABE-B7FE-85EF59363C33` and `/private/tmp/usagi-g7-adoption-matrix.log` remain. Neither failure required a schema/opener change.

The successful direct root is `/var/folders/n1/1q9y8rq16_gdpl5g0kmhbnfc0000gn/T/native-upgrade-DB3FC399-4F8C-418A-B9C1-776C5EE62BDC`. `adoption-outcomes.plist` SHA is `7654e6018d9d9dd64b137f1c9b88f245c74582254be863a4fa157db39e26a691`; `/private/tmp/usagi-g7-adoption-summary.json` SHA is `7c57f469da9fc162aca6af35ceea87d9d77011c9da2555ee4565e9a99cdfd2e9`. Success log SHA is `1b5c4f55f3b0c5cd9150e07f40f0ebda63a1f483665f515177ab42e787561617`; first harness-failure log SHA is `aee66454936e24bdcaf9cdc4d47a8c5492d9676299c4d53888cbf2828f91191a`.

The existing root task now has ten phases and passes in full, including both earlier selected-store matrices. Actions adds the same adoption command with a 120-second bound in its existing lane. Root TOML/workflow YAML parse, with exactly one new phase in each. Mainboard's package pin remains `7776240`; it is unpublished and no hosted Actions execution is claimed. G7 interruption/cancellation, disk-full/protection/power loss, iOS corruption/fresh-process/WAL, wider adoption combinations and real-catalog performance remain open.

### Final receipts for this follow-up

| Check | Result / receipt |
| --- | --- |
| Hosted iPhone | 91 functions / 130 executions, zero failures/skips/compiler or runtime warnings; `test-305cca9df4fd4d9798604880b6c79991.xcresult`; tests report SHA `119a2ff8739839100f3ba3c8321dc79962fa808537259eefa8de326bb81a1874` |
| Shared Mac | 551 functions / 72 suites pass; `VoiceCorrectionSharedMac.log` SHA `d98bb42945457d499aa31f818afbdbe7d5a6f2c546b050773d3c2e30fe42e2be` |
| Native Debug Mac build | Zero errors/warnings; `build-7eb8a13fbd3d4e7aae40cbe221318531.xcresult`; build report SHA `54e08253c97bdabd420cfdd62986d3256142dfab9d17e030ac04660649069b68` |
| Ten-phase persistence task | Pass; `VoiceAssetsAdoptionWorkflow.log` SHA `7b9db14a6a0960dd81a1e3cbc9c14620d8846d99459eb889977b67cd913add20` |
| Parser inventory | 259/259 files parsed, zero gaps/context issues; `VoiceCorrectionInventory.json` SHA `1e7c10ae49f12c9c3904d2c2671603bfdf7c5ffb786531c1bdcf3440f514740c` |
| Scoped Swift checks | All six changed Swift files pass formatter/SwiftLint/UI-parser checks, zero rewrites; `/private/tmp/usagi-voice-adoption-final-lint.log` SHA `c62ac5b2a069af09fdfe1f700b7c3d7196bdfada672f1467481e1ec2fea90678` |

Native logs/reports remain under `.build/Results`, inventory under `.build/Reports`. Final hosted log SHA is `f9a366dd4bbac6198a53ce61e229e671ba2afd1f844cf1f37e40875511baee83`; Mac build log SHA is `930cd82f1ebeab52bb51aec74a909c3ec581c707da45f44a6bac381d18033106`. App-host tests select only `Tests`/`AppTests` with the explicit `--review-fixture` scheme argument. No UI-test runtime, normal account/reset, signed service or new Release run was used. The full Mainboard suite and earlier Release/shared-iPhone receipts retain their previous source scope.

Current source SHA values: Apple capture `133c4eae1e87f689e8945fe8e2901253b1aed06a7ee0f30284153d508a16955f`; input `d0a118ff7f7f65ead240338f1b2e3519d85cbe36c7207b3160eb9779ee3b6fa0`; voice panel `f5a1f41351768bf13c83f7beb07449b8da203fa866014c95e4bbcddb275a5458`; controller tests `8fae7129607cec78e36e977021258e0e213429f123dd2d337b23f064bdb7bf52`; actual input test `c272ac50d7a07b2c1f9618519f648c869d6d2d39133985a4a03bac0d2df1b6be`; probe `f2ac597cfc396239165e5558a38ed330bb66cef94f4365957b974845501f7243`. V1, production generation opener, baseline helper and both frozen fixture hashes remain unchanged from the earlier receipts.

Temporary speech diagnostic source hashes: availability `4d13af5062bdcb22c20adc5636a08de0ca79c8ef40f3c0346af73e6d35224038`; preparation `408a0359d777210984e621b94582beb52549b29463e47b071a0bd91a81a9f384`; final file probe `c5c7978cb4f2279e10fdfa4c87235f6b90eebb2995437cbadf16fdf5f097c345`. They remain in `/private/tmp`, with no app-local development tool added. Result JSON hashes: English `db8e9659dc1b18bdf47b82606d2641389fec4c76cb5425359637915bccf68e71`, Japanese `b60483102dd8e3fe0e94c8c79feca39dcf6746131067b8e4f952433e8b9081a8`. Input AIFF hashes: English `ff7b07ecd430ab09bdacd3825b76c632ce81404ef4a2b70ba523c3f6ce62f933`, Japanese `8cfbfac8f00b67db40f0c5f045a6cd01bb9d048a960286f6126bd842c00f9cd8`. The initial diagnostic error log SHA is `00c3dd2375764e1196a3e53eadce50af0878609c9d40030b0dc3c3a23921a1f6`.

This follow-up adds 16 production and 270 test physical lines: 145 production files / 21,552 lines; 109 test files / 24,561 lines; five tooling files / 281 lines. It fixes readiness/input behavior and strengthens failure acceptance; it makes no LOC reduction or complete-modernization claim. The three protected owner edits remain untouched and excluded from this work.

## Frozen iPhone WAL and current Release acceptance

The next follow-up changes only the existing `FrozenNativeStoreTests` function, parameterizing base versus committed-WAL input. Before the WAL case, the test opens a disposable copy through the existing unversioned writer, verifies all 38 frozen records, saves a revision-checked note containing newline/NUL/supplementary text, and requires every other record to remain exact. The saved material and changed revision are read back. The base database bytes must still equal the pinned frozen database, while a nonempty WAL carries the new commit. The old writer remains alive and quiet through adoption so deinitialization cannot checkpoint/remove that WAL.

Both cases pass through the actual production opener on the iPhone 18 Pro / iOS 27 simulator. The test preserves the complete source/retained store families, compares all 38 adopted records, reopens the selected actor, saves a further note edit, and reopens again with exact selected state and unchanged selector. The original fixture and baseline remain byte-exact. This closes frozen **same-process iOS WAL adoption**; it does not establish abrupt-process iOS adoption/reopen, mid-copy interruption, physical protection, disk-full or power-loss handling. No production/schema/opener, fixture, test helper, app service or target configuration changed.

| Current check | Result / receipt |
| --- | --- |
| Shared iPhone | 551 functions / 828 executions, zero failures/skips/compiler or reported runtime warnings; `test-b78cc80d781c4395bfc5a1777ac7295f.xcresult`; tests report SHA `def62d0a78e7cdca32a206b5bdb4b4cbf4075cc023e706b8b9ed08f60a131964` |
| Hosted iPhone | 91 functions / 131 executions, zero failures/skips/compiler or reported runtime warnings; both frozen-store parameters pass; `test-6075f54ab6d2450ba3fbaa462f06b957.xcresult`; tests report SHA `4ed4409aa6a04800f58ef7faeeb8fbf659ed6243c0e5dde097a46a524ecc5db9` |
| Release iPhone simulator | Pass; zero compiler errors/warnings; `build-0497d765adb7402291ac01aad590a28e.xcresult`; build report SHA `12ef43facc6c73e3a96379a752bc5783da7cfa5344b9318ff33f2d80c88c8ae0` |
| Release native Mac | Pass; zero compiler errors/warnings; `build-91345b9e879849d9a60c1eeb298567ec.xcresult`; build report SHA `e1e1c7918640c0ccc2322d2156bf84c3b58d9ccf6edfb3a8621816fcdc9ce62f` |
| Full parser inventory | 259/259 parsed, zero gaps/context issues; `FrozenWALInventory.json` SHA `a568799d48ef939e23ed7ed9a5e581d538eeb4ea75b012fb8b7e987f30679fa4` |
| Changed Swift file | Formatter/SwiftLint/UI-parser checks pass with zero rewrites; source SHA `f6f90f0d1bdfb7b203faef8867abaadc145e7b5897d594de4dd13875e7784bd6`; `/private/tmp/usagi-frozen-wal-lint.log` SHA `c5c20f840921c551f511eba744b327c5e1024749779178f9601582491ddca01f` |

Release builds use current production sources from `c2f148035d3f2a0e4c224719a3bdc3ace72339ef` and the existing caches; they are not new clean-restoration runs. The new test source is outside Release app membership. Separate App Intents metadata-extraction notes still print; the older retained WatchKit storyboard deprecation is not declared resolved by an incremental build that did not recompile it. The initial Mac invocation selected the app folder's environment and stopped on a stale-lock guard before Xcode; `FinalAcceptanceReleaseMac.log` is retained, SHA `6396a272ec6e7f62c504c34e21dd9ec44c1e7274eaeff534c5e6e8a5005875aa`. The corrected root-Mainboard invocation passes without changing either lock.

The current built-product audit discovers all six packaged Mach-O files across both Release bundles, including watch products. All twelve `nm -arch all -u` / `otool -arch all -L` calls exit 0. Their output has no FMDB/FMDatabase/FMResultSet/PromiseKit/Hippolyte matches. Both bundles contain the expected installed-app display names (`usagiunagi` for English, `兔鰻` for Japanese/zh-Hans/zh-Hant), `UsagiUnagi` icon metadata and a nonempty microphone usage description. Neither contains the frozen store/baseline/helper, a `native-v0-186c1cc3` resource, or an embedded test bundle/run configuration. This is a bounded resource-name audit; it does not prove every DEBUG symbol absent, optimized-out static dependency provenance, icon rendering, signing, microphone access or App Store listings.

`.build/Reports/ReleaseAcceptanceBundleAudit.json` retains each binary hash, native command and output hash; report SHA `aa82345eda6912bdce64c78e9984095bc97c9ea496913acbbaeae30f840676f5`. The disposable read-only audit source remains `/private/tmp/usagi-release-bundle-audit.py`, SHA `d320c06c9565559b6d3a6442d07b0b64750b7c69264ff38ae794a6a898e26d31`; it runs through root Mainboard and is not another app-local build tool. No dependencies or Mainboard package code changed.

Final log hashes: shared iPhone `aca58ce5a9a39a4e09de53caf52e57d78d00bef18204b919af181a2fb3f1156e`; hosted `c2f8b4a8862684135948320d342db5839300932e623e3976f839b94844f4a8e8`; Release iPhone `c4151abe3cfd61257f3974670e1dfd86fd2de83bdb3939ed97fc208000609bdc`; corrected Release Mac `19dafed0805e3d889b0774c6bb23fc213a03049a1a251a24bab9e2c1488445b4`. Results are under `.build/Results`. Tests remain non-UI, and hosted app launches retain exactly `--review-fixture`; no normal account, reset, real exercise, GUI automation, physical microphone or signed service ran.

The schema/opener and both pinned fixture hashes remain unchanged. Inventory is 145 production files / 21,552 physical lines, 109 test files / 24,597 lines, five tooling files / 281 lines. This adds 36 test lines and zero production lines. Rendered/adaptive usability, hardware/IME and speech capture, signed services/watch, broader G7/device failures and real-account statistics calibration remain open. The goal stays active; this is acceptance progress, not complete-modernization evidence.
