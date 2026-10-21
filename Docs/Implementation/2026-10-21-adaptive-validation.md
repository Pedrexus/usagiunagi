# iPhone-first adaptation and local acceptance

The iPhone study flow remains the product baseline. iPad and native Mac use the same navigation, screens, feature owners and persistence actor. Native toolbar roles, sidebar-adaptable tabs, search, forms, adaptive lesson tiles and the available review viewport determine presentation. No device-name layout switch or generic platform utility layer is needed.

The shared-UI audit at `1e0b3e10` found eleven OS-conditional starting points. They cover input/keyboard APIs, audio interruption, notification permissions/system Settings and activity prediction, rather than alternative feature layouts. Keep these boundaries explicit and narrow. Hiding them behind flags would not remove the API differences. The Japanese answer input remains an intentional UIKit bridge until SwiftUI can preserve its input-language, marked-text and caret behavior.

Rendered acceptance is still required for iPhone portrait/landscape, keyboard presentation, larger text, iPad multitasking and compact/resized Mac windows. Device Hub access was denied; no alternate GUI capture or automation was used. Source and compiler evidence do not establish those interactions.

## Content-fit lesson selection

The renewed priority remains iPhone first, with automatic adaptations of the same feature flow. Existing `StudyTabs` uses Apple's [sidebar-adaptable style](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable): iPhone tabs, adaptable iPad navigation and the native Mac sidebar. Root/review actions already use semantic toolbar placements. The remaining eleven shared-UI OS-conditional starting points still configure keyboard/input, audio, notifications/system Settings and activity APIs; none chooses a separate screen layout. No platform capability wrapper was added.

`LessonPickerView` now uses [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits) for the selection footer. The row requires the count and Start button to fit at their natural widths; its flexible spacer preserves the original leading count and trailing action. The fallback allows both controls to grow in a vertical stack. This replaces the footer's text-category-only `AnyLayout` choice and handles narrow space or wider text without another breakpoint. The existing tile accessibility sizing stays intact. Only stateless presentation appears in the alternatives; selected IDs, busy/error state and the asynchronous start operation retain their picker owner. This adds seven physical Swift lines for the explicit fitting alternatives; it is not a LOC reduction.

After the production edit, scoped Mainboard parsing/UI rules, strict swift-format and SwiftLint all exit 0. Existing root Mainboard Release tasks also exit 0:

| Check | Receipt |
| --- | --- |
| iOS simulator Release | `build-8e19fe8bd2b54da99b9d6bc69d317ef3.xcresult`; zero compiler errors/warnings in this incremental build |
| Native Mac Release | `build-15031790aec241a08d16c7082d0d8776.xcresult`; zero compiler errors/warnings in this incremental build |
| Source SHA-256 | `a53172db85d733e9ae4924241c7b59e0a03fd3e083f86116cec1e10812f28d57` |
| iOS log SHA-256 | `82e628d6a00a87dfcbfaa8d6c17a742c4c8c32058797ec042e03ebdf6a6f8cbd` |
| Mac log SHA-256 | `7261b23b0fa20382fd010595f4f6f9402639f7049a461a780b02cd286aa8b94e` |

Logs are `.build/Results/AdaptiveLessonFooterIOS.log` and `AdaptiveLessonFooterMac.log`. No new tests were added for this presentation-only edit. No runtime UI or real account was opened. The abrupt-store-exit prototype was not included in this UI checkpoint; its subsequent acceptance is recorded in the [durability follow-up](2026-10-21-frozen-ios-and-review-focus.md#abrupt-iphone-wal-reopening). Historical watch warnings and outstanding rendered/device gates remain open. In particular, verify footer reachability, one lesson-start operation, selection/error retention and the surrounding toolbar on iPhone portrait/landscape and large text, then iPad multitasking and resized Mac windows once fixture UI access is available.

## Shared scene activation and window defaults

Foreground sync now has one start point in `StudyApplicationWindow`'s shared active-scene task. The Mac-only start in `StudyApplicationOwner.prepare()` is removed. Services still have one app owner and shared preparation; explicit iOS background work still uses `refreshInBackground()`. A worker that has started remains app-owned when individual windows disappear. Initial foreground monitoring on Mac now waits for an active prepared scene, matching the iPhone entry path.

The task's private Equatable identity contains both `ScenePhase` and service readiness. A successful Retry publishes services and changes the identity even while the window stays active; phase changes still trigger preparation as before. This follows Apple's [task cancellation/restart contract](https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)). The selected compiler rejected a tuple as a generic Equatable ID in a standalone SDK probe, so the two signals use a small local value type. No passing app build is attributed to that failed probe. Coalesced preparation remains independent of the waiting SwiftUI task's cancellation.

`defaultSize(width: 1120, height: 800)` is shared outside the Mac guard. It specifies an initial native window preference, with [system clamping and restoration behavior](https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:)); it is not a minimum content frame. The remaining Mac guard protects [default launch behavior](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)) and [disabled restoration](https://developer.apple.com/documentation/swiftui/scenerestorationbehavior/disabled). Official documentation and Xcode 27's public SwiftUI interface confirm those two APIs are unavailable on iOS, even though the general restoration modifier exists there. No screen, toolbar placement, typeface or WaniKani color changes in this follow-up.

The original pinned `SceneDelegate.sceneDidBecomeActive` starts reachability and refreshes the main screen (lines 63–68), consistent with active-scene entry for the iPhone flow. The new app retains its modern app-owned worker and multi-window read gating. One OS guard and a duplicate start are removed; the typed task key adds one net physical production line across the two files. This is a shared lifecycle correction, not a LOC-reduction claim.

| Check | Result / receipt |
| --- | --- |
| iOS simulator Release | `build-227a74c70ac64ec9af197931fca77cc0.xcresult`; zero compiler errors/warnings; `.build.json` SHA `2fc23030160149c8c38f361b3ff062cda4074d909885931ec81b34accf485cb6` |
| Native Mac Release | `build-28497795b3ad42978823f0ba21f8d100.xcresult`; zero compiler errors/warnings; `.build.json` SHA `92177c8051c786a8da56e29e7d2ae76db35aa8734861f6ac71150a9b7e4d341f` |
| Regular iPhone `Tests` + `AppTests` | `test-12fa044749bf408d84323b35febab359.xcresult`; 95 functions/172 executions pass, one declared restart-task skip; zero failures/compiler/reported runtime warnings; `.tests.json` SHA `521a02c414e704bd1fbacc6baa7b6fa1729efe7568d4fc9be9d9ffb959296b28` |
| Shared Mac `AutomaticSyncTests` | 18 functions/one suite pass; `SharedSceneSyncMac.log` SHA `096ef21319ac388d075e7b90fe698e5954d4495e6a33b93744141d9a04938383` |
| Mainboard bundle policies | Five iOS binaries and one Mac binary, all architectures checked; both reports successful with zero violations and four localized names each. `SharedSceneBundleIOS.json` SHA `f1be2300c8475a5d3495d4e5d32e491daad305bf6edcb55cc7c47d673711bc52`; Mac SHA `812a563ef65ebf8ffa4a81f0a35d3204a7f9b5191a72ade4ec927002abd80846` |
| Scoped parse/UI rules, strict swift-format and SwiftLint | Exit 0 for both changed Swift files; `SharedSceneLint.log` |

Source SHAs: `UsagiUnagiApp.swift` is `db050834f0f9bf68a5ec69073ecf80f5093755ca362549f06a676835a743c6a7`; `StudyApplicationOwner.swift` is `d9af54c681f0a2ca7d206177caa0e78ac0a8422931fd10cf9aaf2e99d286a8f1`. Logs under `.build/Results`: `SharedSceneIOS.log` SHA `c1b69600c53015221cc064be83d4427ccc3004839b7fa835c51fa3b080b2d6bd`; `SharedSceneMac.log` SHA `390a8669277c0d0d67255cc743dd0542d6e419d24e6dcec81a45ac506e5cfaef`; `SharedSceneAppTests.log` SHA `90eb8457160999ac5d44590d89d7ac7d325d31110853f4d96f143330320dd631`.

The existing tests cover shared preparation/cancellation, explicit retry, headless confirmed-work delivery, expired background work, offline/reconnection/uncertain-write behavior and multi-window read gating. They do not exercise SwiftUI's on-screen Retry-to-activation transition, iPad initial sizing, Mac activation/restoration or window closure. Those require fixture UI access and remain open. Incremental zero-warning builds do not erase historical watch warnings. No normal account, real exercise, GUI workaround, microphone, signing change, push or hosted Actions run occurs. Storage schemas, frozen migration fixtures, speech and statistics are unchanged; their earlier evidence keeps its original scope.

## Shared hosted unit tests on iPhone and Mac

Both hosted unit-test targets now use `SDKROOT = auto`, explicit iOS/macOS 27 floors and the same `TEST_HOST` expression: `$(BUILT_PRODUCTS_DIR)/Tsurukame.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tsurukame`. Xcode's resolved Mac settings supply `Contents/MacOS`; shallow iOS bundles need no intermediate folder. Native runs prove both forms work. This uses one app and the existing test bundles, with no new harness, product source or per-platform host-path formulas.

The existing Foundation archive importer/schema are added only to the Mac `AppTests` compilation. The shipping Mac app still excludes those iOS legacy readers. The older `Tests` target explicitly declares its already-pinned SwiftProtobuf/WaniKaniAPI products, which it previously obtained through the iOS host's dependency graph. No dependency version or generated-source policy changes. Japanese text-field tests are an iOS build member, and the two actual `WatchHelper` tests retain an iOS-only block. Their assertions are unchanged: native Mac has neither the UIKit field nor the WatchConnectivity adapter, while common preferences, archive, service, font/audio/cache, statistics and persistence assertions run on both SDKs.

The first native Mac control stops before launch with status 70: `AppTests` inherited `Debug-iphoneos` and a shallow executable path. Fixing that target exposes the same preflight failure for `Tests`, even when only one suite was selected. Once both hosts resolve, a third compile stops with status 65 because the legacy tests lack explicit protobuf products. These three failures retain zero executed cases and are not accepted as test passes. The corrected build first passes all eight `NativeAppAssemblyTests`, then both complete non-UI bundles pass through the canonical locked app-manifest tasks.

| Check | Result / receipt |
| --- | --- |
| Full native Mac `Tests` + `AppTests` | `test-5f2c0de068c642609deeee699dd20661.xcresult`; 83 functions/160 passing executions, one declared restart skip; `.tests.json` SHA `1801ff69371c84209392d3c2ce644fe5d0048358a668cdff2457f7cd7056b7ef` |
| Full iPhone `Tests` + `AppTests` | `test-d0b458be18304fee8aa36784f7e69bae.xcresult`; 95 functions/172 passing executions, the same declared restart skip; `.tests.json` SHA `d7fc481bc1db0de34fefac199d2651dfd694cf7946ff0a77b7ff1463f6a8a0d6` |
| Mac service-assembly pilot | `test-7de44cdb65be40c9b9d8c70bd9ac92d3.xcresult`; eight functions pass without failures/skips |
| iOS simulator Release | `build-8ec3520931324678a384cb2dccf02421.xcresult`; `.build.json` SHA `20b1b0657050cfbcef425a1e3ef87c8f2b363c9f916028c891df445bd8b28655` |
| Native Mac Release | `build-d8a75d6032fd478cbc2ab74607a916db.xcresult`; `.build.json` SHA `a02426bfbc73ec7bf351e9ce822b4c82654170d1e5215bd1b38b0216d8f4ff32` |
| Bundle policies | Five iOS and one Mac binary pass all architecture/name/resource/library policies with zero violations. `SharedTestsBundleIOS.json` SHA `f1be2300c8475a5d3495d4e5d32e491daad305bf6edcb55cc7c47d673711bc52`; Mac SHA `812a563ef65ebf8ffa4a81f0a35d3204a7f9b5191a72ade4ec927002abd80846` |

Both final native test summaries have zero failures/compiler/reported runtime warnings, and both Release summaries have zero compiler errors/warnings in their incremental scope. The twelve-function platform difference is exactly ten Japanese-input functions and two WatchConnectivity functions; no iPhone assertion was dropped. Scoped Mainboard parse/UI rules, strict swift-format, SwiftLint and native project-plist validation pass. Root/app TOML and Actions YAML parse; the old `usagi-test-app` parent alias delegates to the same locked iPhone task instead of retaining another command.

Actions invokes `test-app-ios` in its existing iPhone lane and `test-app-mac` before native Mac UI acceptance. The Mac lane now shares `UnifiedMac` derived products and has a 45-minute job bound for the additional required stage. Existing UI steps remain required. Mainboard stays at the same unpublished `b72cd6f` pin; no push or hosted result is claimed. TestAction still supplies exactly `--review-fixture`; only non-UI tests run locally. This does not resume the denied GUI automation, authorize real account/exercise activity or establish keyboard, window, voice, signed-cloud/watch or physical-device behavior.

Current hashes: project file `f1459d78d77067e8a2e0341822e8471dad8180cc8411a2f8e12336d799a32725`; notification test source `b0e603b73228b84e254781ae37f61be65ae6eb30c507fe27133b6ff2dddb5d1d`; app manifest `387514fa299239a98b8790c3411ae9a52256e547a5e6f6b2419a4ab5fb9db314`; workflow `ee9870bbc1dc50c2ea7149cd669ce9df016feedebd1506a8fa108434fd4d0a87`. The 446-byte empty app lock retains SHA `fcb0c110b128cd94ac8f10d66ee254a8635b6cadddae308c85fbde71f8910897`. Shipping Swift files, V1 and frozen writer/store/manifest are unchanged; the three protected owner edits remain intact. No additional broad shared/Mainboard suite run is claimed.

Logs under `.build/Results`: `SharedMacAppTestsAll.log` SHA `4219c970233983f465693cda096a4e2192d6e87b2ebcc070d2f091962b079fe9`; `SharedIOSAppTestsAll.log` SHA `e3f67ed468343045b42a401b1a0a8345e3d556e680ea7214e1693ff864d41e11`. Earlier failed logs `SharedMacAppTestsBefore.log`, `SharedMacAssemblyTests.log` and `SharedMacAssemblyFinal.log` remain separate; `SharedMacAssemblyPackages.log` contains the passing pilot. Native build-setting probes retain only the queried SDK/bundle-path fields. Broader source/GUI/service acceptance remains in TASKS.

## One hosted unit-test target

The next cleanup consolidates `Tests` into `AppTests`, keeping one hosted unit-test target and one `App/AppTests` folder for iPhone and native Mac. Six Swift files move without byte changes. Their existing source references join the common target, which retains explicit protobuf products, native SDK selection and the shared executable-path formula. The old target, empty build phases, duplicated configurations, scheme entry and handwritten test Info.plist are removed: 136 project lines, 14 scheme lines and 22 plist lines, or **172 physical configuration lines** overall. No production Swift or assertion LOC is removed.

The canonical frozen writer and store remain under `App/Tests/PersistenceProbe`; only their project group-relative references change. The UI-event JSON files and probe package also stay at their existing paths. Archive readers compile once into the merged target on either SDK; the shipping Mac app still excludes them. UIKit field tests and WatchConnectivity assertions retain their iOS scope. Mainboard's two existing app-unit tasks now select only `AppTests`; parent proxies and Actions consume those same tasks without another command or lane. Current scheme XML enables only `AppTests` and exactly `--review-fixture`; the current native trees contain one unit bundle. Older generated `.xctestrun` files predate these direct test runs and are not current acceptance evidence.

| Check | Result / receipt |
| --- | --- |
| Full iPhone `AppTests` | `test-80280113f97245bba200ad3b10c6d970.xcresult`; 95 passing functions/172 executions and one declared restart-task skip; tests report SHA `7d19a5491a72b6bb91b50b3299e07e9017cf65294b3969a7f733708a23fa0566` |
| Full native Mac `AppTests` | `test-7ece2151408b4fbeab62a6fc6c897d2b.xcresult`; 83 passing functions/160 executions and the same skip; tests report SHA `3bfc7d834f098527bb866d8da0e51bd82843a2f3a4ac0cac3e56daaf0d456c7e` |
| iOS simulator Release | `build-4a4bc3bd00cf4a0ba06a103718d2bcb1.xcresult`; build report SHA `01687ed0ed8b9c69b0eb05f734742ae60ab54cb8e0d115fb9f6140d4de96c090` |
| Native Mac Release | `build-f90418d00fb94745a2e987052c64ae2a.xcresult`; build report SHA `ac90e4abb7627a3f54c81cc7d293ea0614176ef92b1fe05ed307073adb65da2d` |
| Bundle policies | Both successful, zero violations, five iOS binaries/one Mac binary and four localized names each. `OneUnitTargetBundleIOS.json` SHA `f1be2300c8475a5d3495d4e5d32e491daad305bf6edcb55cc7c47d673711bc52`; Mac SHA `812a563ef65ebf8ffa4a81f0a35d3204a7f9b5191a72ade4ec927002abd80846` |
| Scoped source checks | Mainboard parse/UI rules, strict swift-format and SwiftLint pass on the six moved files, zero rewrites. `OneUnitTargetLintConfigured.log` SHA `c62ac5b2a069af09fdfe1f700b7c3d7196bdfada672f1467481e1ec2fea90678` |

Both test summaries have zero failures/compiler/reported runtime warnings. Incremental Release summaries have zero compiler errors/warnings; historical watch warnings are not erased. The prior two-bundle native trees and new single-bundle trees have identical function identities and all 89 parameter-case verdicts after the expected `Tests`→`AppTests` module rename. The `RecentMistakesTest` merge arguments encode Swift dictionary descriptions with nondeterministic entry order; comparison sorts only those numeric dictionary entries, retaining all keys, values, names and verdicts. The first raw argument-ID comparison failure remains in `OneUnitTargetRawArgumentIDs.log`. No source/test change was needed. The successful comparison log SHA is `87f04d1aafa63d9d552b39d00c4ee8a6a2495aed9024df18b82967feef997650`.

Before/after Mainboard inventory reports have identical per-file hashes, imports and classifications after the six path mappings: 259/259 Swift files parsed, zero gaps/context issues. Totals remain 145 production files/21,590 physical lines, 109 test files/25,635 lines and five tooling files/281 lines. These are source-path classifications, not target membership. `UnitConsolidationBefore.json` SHA is `fd28e110fe1078d149c0e96b3d308d152943e0f6cd72526486890c0d4ae3353f`; after SHA is `7936f3515da8f5042cc1e0a032aa3c3d60d88075e384f048a8aff141938f0caa`. An initial lint invocation requested an app-only `swift-parse` tool from the root configuration and exited before checking files; the corrected configured `swift-ui` step includes `SW-PARSE0001` and passes alongside both linters.

Project SHA is `b3800e9c40778df930624a98ab3633c92b88cbcfea2676ef795d68715c1d4419`, scheme SHA `ccdcd528576a1808e52b11c2113ea69b7a88a520b2b151412c6c861a3a7f06b7`, app manifest SHA `64569a8567eea7bf38a91d4ea74404fd073555f664b64b4afce33bf449cfc165`. Shipping Swift, frozen V1/writer/store/manifest, dependency lock and the three protected owner edits are unchanged. The separate four-phase restart protocol retains its existing scheme/target and previous receipt; it is not rerun or claimed fresh for this configuration-only consolidation. No GUI automation, normal-account launch, real exercises, physical/signed services or hosted publication is claimed. Current rendered iPhone/iPad/Mac acceptance remains open.

## Typed startup comparison and synthetic scale

The internal migration snapshot previously serialized the complete schema/record aggregate into an opaque `Data` value, then serialized that blob again when producing an activation digest. Every selected-store reopen built that unused outer encoding too. `StudyGenerationSnapshot` now directly owns the existing typed headers, records and handoffs. Synthesized `Equatable` preserves dictionary/member and handoff Set semantics; per-field canonical JSON bytes, sorting, duplicate-identity, complete-attribute and empty-store checks are unchanged. All fifteen persisted Codable paths still pass through the corruption guard. No validation read/check is removed.

Adoption also reuses the candidate snapshot already compared with the source instead of taking the same full snapshot again before activation. Its actor has not been exposed to another caller, and physical-schema/source/retained checks, synchronization and cancellation still precede selection. This removes one wrapper type and **five physical production lines**, adds no abstraction/platform branch, and changes neither persisted V1 models nor their payloads. A new private activation digest encodes the typed value directly; existing selected receipts remain valid and are not rewritten.

A temporary Release SwiftPM executable uses the canonical StudyCore/StudyPersistence sources through Mainboard. It creates only marked disposable synthetic stores: 1,000 or 10,000 primary subjects, 100 subjects under a second account with overlapping IDs, twenty primary pending attempted reviews, one hundred primary notes, assignments, snapshots and import receipts. Subjects include Unicode mnemonics/readings and sentences. It verifies exact catalog bounds/counts, assignment/pending/note counts, other-account isolation, preserved mnemonic content, due/lesson totals and catalog pending status. It does not query WaniKani, supply a real curriculum or exercise an account.

The original executable is retained beside the rebuilt one. Each binary reopens the same old-format selected fixture in a fresh process three times, interleaved **old/new/new/old/old/new**. The OS/file caches remain warm; this is a small local comparison, not a controlled hardware benchmark or physical iPhone result:

| Primary synthetic subjects | Original median reopen | Typed median reopen | Observed reduction |
| --- | --- | --- | --- |
| 1,000 | 0.133140 s | 0.115071 s | 13.6% |
| 10,000 | 1.029445 s | 0.883998 s | 14.1% |

Every original/retained family and existing selector hash stays exact across both binaries. Query/home/catalog correctness checks pass on all runs; no query speedup or memory-usage claim is made. The original 10,000-subject first adoption took 3.335 seconds; no comparable new-adoption timing is claimed. Benchmark source/manifest copies are retained under `.build/Reports/ScaleBenchmark`, SHA `4a41a7207e6dfea247b813f7f78013214160a57b8c81d58d89666c45590dc319` / `3f1255bf279d03138cff82f90dc88cc8c4ae6a69cc2c57e5c3e3f56307bb167e`. Baseline/rebuilt binaries have SHA `92725c9b58670b8335cf1c875c410e17248405f745a51f390889ef3ee97712c2` / `2cc0c0686670c3db1f7a4833a8bd584457cdd8b0288e27790b279cad3d9d13f3`. Paired log SHA is `d1cd46313c457529ef19cd741c298bab6e1db3f23f0cfe48fe88d1a5e7f0b8c1`; samples SHA `1aaa908e3e9785fdded0289ea5c57e6c75f08fdb350faa83156b62761aec17df`; preserved-state hash receipt SHA `663a558aebbf45c6e3097eac9000df47cabd8843ac02149fcac99d92dcf62e0c`.

Two setup failures remain separate from app evidence: the temporary helper initially put a throwing read inside a nonthrowing precondition, then its path guard trapped before calling the opener because existing temporary URLs canonicalized `/private/tmp` to `/tmp`. The helper now derives both paths from its canonical existing parent. `ScaleBenchmarkBuild.log`, `ScaleBenchmarkBefore.log` and its own `StartupScale` crash report retain those failures; `ScaleBenchmarkBeforeCorrected.log` is the successful baseline. No app crash or production URL fix is attributed to them.

The complete shared suites pass after the production change: Mac **556 functions/72 suites** (92+8+206+250 across its four native runs), iPhone **556 functions/839 executions**, no failures/skips. iPhone result `test-7fde4e8b2c7c41e2bf6330ef229e93d1.xcresult` has tests report SHA `2465f55819ea8fecc1891600f083425939989a8bda16e9e886e54ffe482421a6`. The complete ten-phase Mac persistence task exits 0, retaining exact frozen values, source/retained bytes, separate-process restart/lease behavior, 26 payload refusals, five metadata refusals and first-adoption retry controls. Shared Mac/iPhone/process log SHAs are `c2d5b62c2fe8609017b4cef4ed9b03c934c673317a34c715546d102534a232a9`, `ae826d88dbe459b579e2a03dcfd639dd912a826bbafc1bd22877a03a5da5a82d` and `f69bc48204894aa18c41601f7cc95b1ea755ac9546f9bfb26c584563a652ede8`.

The eight-phase iPhone restart task also exits 0 with UUID `62A6627B-9A97-421E-AED7-5524DBE34DFF`, preserving all 39 saved-review records and all 38 records after opening interruptions. Verification PIDs are `22273 → 22732`; candidate PIDs `23012 → 23305`. Native counts and all three explicit exit-86 failures retain the previous contract. `.build/Reports/TypedSnapshotRestartEvidence.json` SHA is `4ba3179a753ea2217a200aaa61395e24e44c085a2a2fe9eeb7cfbee1b134853c`; task log SHA `29a7c6b08a351b916b35266a023cb510d2d6c5188873a6396c98aaba5686ffce`.

| Final current-source app check | Result / receipt |
| --- | --- |
| Regular iPhone `AppTests` | 95 functions/172 executions pass, one declared restart-task skip; `test-7cd6bfec6c5c4448b040248efabc3f75.xcresult`, tests SHA `c374cec79a21ca316dc1631cee90384c1d5a763ff3f06d90022093b047c20461` |
| Regular native Mac `AppTests` | 83 functions/160 executions pass, one declared skip; `test-e1ffae541e734c4f97ddf7293ba317e5.xcresult`, tests SHA `10b2f8f9440b4909ef8ed16d293f253c22b52ed35f3e93483ca0b0b74e95f8a9` |
| iOS simulator Release | `build-486b94bcfe1645db8dfd2d4346133994.xcresult`, build SHA `3c9a563c10154d65ec34f1e5a30d827b5d161bb68f7dd2afe862d8f730dac199` |
| Native Mac Release | `build-0b4c86e2a66f4d50854d262e92ae48bc.xcresult`, build SHA `0a185e549171246cf6659d3029952de82d5fff9eedcfe82ae29b052734029ea0` |
| Release bundle policies | Both successful, zero violations, five iOS/one Mac binary and four localized names each. iOS/Mac report SHAs `f56b7963b00765de672031b9e582d6c72ae62385f17d401b564d6a7a880fb070` / `1253aca6ab2e1c3238ef823288e5036fa63e96cb56aba931dc43803e7db43b8c` |

Final native summaries have zero compiler/reported runtime warnings and no ordinary test failures. Incremental Release summaries have zero compiler errors/warnings; the historical watch-host warning remains historical evidence. The first Mac unit start overlapped the Release command in `UnifiedMac` and failed before launch with a locked Xcode build database: `test-8898ce3905fb46499305f7fb79cdfe64.xcresult`, zero executed cases, `TypedSnapshotAppMac.log`. After the Release handle completed, `TypedSnapshotAppMacSerialized.log` passes on unchanged sources. This invocation failure remains distinct from app behavior and is not counted as a pass. Keep operations sharing derived data sequential.

Both changed Swift files pass Mainboard parse/UI rules, strict swift-format and SwiftLint with no rewrite. Snapshot/opener SHAs are `8e27f367e7659bafd61de40cffb8ebeda8ef9511e2ce28fff37ccd9f0ddd199c` and `8d0f4da0b3937c0ec5d75e2c0bbf3a8dbb554f1ef96cfaa957b33681b5d26b33`. Inventory parses 259/259 files with zero gaps/context issues: 145 production files/21,585 physical lines, 109 test files/25,764 lines and five tooling files/281 lines. Inventory SHA is `d27764e45c7431ecadd24eda5847c85cc1112f29e928e0a24bd9da8cc432e295`. Counts classify paths rather than logical LOC or compiler membership. Real-catalog/device performance, rendered acceptance, wider interruption combinations and signed/physical services remain open. No normal account, exercises, microphone, GUI workaround or publication occurs.

## Clean source restoration

A fresh `git archive` of app commit `1e0b3e10d1e41531132b7b2ddc93125a98a0f63d` was unpacked into `/private/tmp/usagi-clean-source.ypceQO`. It excludes all working edits, including the three protected owner files. Xcode resolved the committed package pin and built Release iOS and macOS into separate initially empty derived-data folders through root Mainboard.

| Check | Result |
| --- | --- |
| Explicit iOS resolution | Exit 0 |
| Release iPhone simulator | Succeeded, zero errors, one retained WatchKit storyboard deprecation |
| Release native Mac | Succeeded, zero errors or warnings |
| SwiftProtobuf checkout in both derived-data folders | `3d537cb81aef272a03cb3be815439e9bf0eb3bd3` / 1.39.0 |
| Committed resolution before and after | SHA-256 `a44a404aa92b7f6ac990e3e55f8ac198fd0f027aeb97c5c31ddfeaf09f9ed009` |

The native results are `.build/Results/build-e5982e39b0864507adac58bb187436cf.xcresult` and `build-7a9c65a065eb483f93bd098a0e667d81.xcresult`. Their readable report hashes are respectively `a38c666aa920b0b64b53e1daae19591d925f43785a29c682af6cd6858c8a4111` and `88d4714f852295853fab808159efa7e11c1adbd3c371faea3a251f95ed9834f1`.

Resolution/iOS/Mac log hashes are respectively `cb21a9dbbdeeb21e1e4f919f3e6d01512da1328a511ed96a681d06b68aef6869`, `2e821302ccc57e045e8cc7130d93dfd2143644c216a96c821682b2554efc31eb` and `f65cd06ec4f6708673af70eaf5d0bca49dacf9474635b31d65380a04f02bdbd6` under `.build/Results/CleanRestore*.log`.

This proves restoration from committed app sources into fresh checkout/product folders on this Mac. SDKs and global SwiftPM caches were retained; it is not an air-gapped build, a hosted CI run, signed-device validation or acceptance of later working changes.

## Watch snapshot validation

The saved widget mirror previously bypassed the phone packet's numeric validation. A decodable mirror containing a negative learned count and a very large total could overflow the level display. Both read paths now apply the same validation, leave malformed input untouched and retain the raw selection (including historical value 2). Private defaults keys, bundle identities, packet timing and the existing forecast policy remain unchanged.

The concrete cache accepts only a defaults-suite name and mirror URL for isolated storage checks, retaining its `Sendable` value type and existing production callers. No general storage layer or platform utility was introduced. The production file grew from 144 to 162 physical lines; this is a correctness change, not a LOC saving.

The actual cache source and its new tests pass on Mac through a temporary SwiftPM target linking the canonical files, and on iPhone through `AppTests`: **15 functions, 25 invocations, one suite**, no failures or skips. Mac test duration was 0.032 seconds; iPhone 0.095 seconds. The iPhone native build summary has zero compiler warnings; AppIntents metadata extraction separately emits its existing no-framework diagnostic. Both generated hosted-test entries retain exactly `--review-fixture`. No normal defaults, App Group, account store or watch app was opened by these tests.

Cache/test SHA-256 values are `62470c280f326859b6deba48da833467835acbb31952a77e0280a3a8b4ae0894` and `2550b3c8bb1a337ad47c2a9b5abdf88608ada1d965d64bb960470556c1a70b24`. Mac test log hash is `e1d341940cb8134e3a4042ce676eb130cea2a9d3e73005ab32b12124a9f22d26`; iPhone `.build/Results/AdaptiveWatchCacheiOS.log` hash is `7afe0327852c72f732219138bba0c945ee1953796bc8e08b8b3a540cb2bf3901`. The iPhone result is `test-e3b8e4da445f48a7b38d43f27f3ff4a3.xcresult`, readable report hash `8a720e9a757e28ed4a3c37d352a8beb7900facdaa0042675d767435f1bd8acfa`. Scoped Swift formatting/SwiftLint pass with no rewrites; project syntax and whitespace checks pass.

Tests cover malformed/missing/unknown fields, preserved raw selection, valid zero, two-hour cutoff, hourly projection/overflow/expiry and failed atomic publication. Signed App Group access, installed-face upgrades, physical background delivery and the final watch lifecycle conversion remain separate gates.

## Malformed persisted values

The new disposable corruption diagnostic modifies one selected-store JSON blob after a verified frozen-store adoption. A malformed nonoptional account state and a malformed present optional material issue both terminate the actual opener child with signal 5 in `CoreData/PFFaultingTransformedValue.swift:28`: the framework uses a failing `try!` while decoding the value. Ordinary Swift `do/catch` does not handle this failure.

That baseline diagnostic exited 1. Original, retained and selection bytes and generation names stayed unchanged; the already-corrupted selected input stayed preserved except for shared-memory bookkeeping. No empty replacement or fallback was observed. This was a real failure, **not safe refusal**, and does not identify the cause of an owner's historical crash.

The first report is `/var/folders/n1/1q9y8rq16_gdpl5g0kmhbnfc0000gn/T/native-upgrade-7BE247AD-B42F-45F6-AF50-7C67DB8BAA6F`, with `/private/tmp/usagi-g7-payload-probe.log`. It remains a failing historical receipt.

### Production safeguard

The existing generation owner now validates saved Codable data before creating an existing-store SwiftData owner or reading an adoption verification image. It uses the public [cached model API](https://developer.apple.com/documentation/coredata/nspersistentstorecoordinator/cachedmodelforpersistentstore(at:options:)), compares its complete entity hashes with store metadata and the public [model builder](https://developer.apple.com/documentation/coredata/nsmanagedobjectmodel/makemanagedobjectmodel(for:mergedwith:)-7lqq9) for the unchanged frozen V1 declarations, then requests key-path expression projections with a [binary result type](https://developer.apple.com/documentation/coredata/nsexpressiondescription/resulttype).

Every schema-derived Codable path must have an explicit typed JSON decoder. Unexpected values, nonoptional NULL and unknown/missing mappings refuse opening. Optional NULL stays optional. The read-only Core Data store is removed before normal SwiftData opening; normal feature queries and writes stay unchanged. Public documentation defines these APIs; raw-byte behavior is experimentally verified on Xcode 27, rather than promised by those documents. Plain dictionary property projections first failed with an unregistered adapter, so they are not used.

The actual production-opener probe now exits **0**. Both intact runs restore 38 exact frozen records. After one account state or present material issue is truncated, each child exits **74** through caught `StudyStoreOpeningError.invalidGeneration`, with no signal, returned owner, fallback or empty replacement. Original/retained/selector bytes and generation membership are unchanged. The selected DB/WAL remain unchanged; selected SHM bookkeeping changes, as allowed for an active mutable generation. The actual opener works directly on its lease-owned selected store and creates no per-launch clone/backup artifacts.

The existing process regression also passes: frozen base/WAL adoption, lease refusal, abrupt-exit answer/note commit, two separate 39-record reopens, and fresh empty install/two reopens. Shared Mac and iPhone suites pass **551 functions/72 suites** after the guard, including **827 iPhone executions**, with zero compiler warnings. The frozen fixture exercises fourteen populated Codable field paths; `ReviewRecord.issue` is NULL, while its identical optional issue decoder is exercised by populated material issues. This is not an independent historical decoder freeze or an exhaustive corruption matrix.

Production SHA is `8aa5358e3fc021452a1d0bed017b1418012e0fba0946c56964da0af0e8d95b1f`; probe SHA `d85a7d6c9b42af3f64addac132a60cb14529f3331c0f9637a7e07381fdab55a6`. The frozen V1 remains `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`. Successful corruption reports are in `native-upgrade-81F11483-9FAF-42F0-BC55-C22E04AE1DCA` under the same temporary parent. Log SHA values: production corruption `f7794cc113b1cf6f3420b818d02a62d6d4cbcf29e76f7ce89d1a1ef1970de7c9`, intact process regression `618f12a5b50b9edd78fc640a5b73f3082044ead888e4b77f872d888b3ffb7714`. Scoped Swift formatting/SwiftLint pass with no rewrites.

This adds 99 production lines and an account-wide startup read, one entity at a time. Real-catalog/device performance, frozen-store iOS adoption, malformed metadata/model caches, disk-full/file-protection/power loss and wider G7 failures remain open. Silent defaults, schema edits and store resets are not remedies.

## Final app checks

| Check | Result and receipt |
| --- | --- |
| Shared Mac | 551 functions / 72 suites pass; `AdaptiveSharedMac.log`, SHA `be3a4b6b6d39a4a32620f42636846ce8f5c4699a281efe1f243cce64b568d7ed` |
| Shared iPhone | 551 functions / 827 executions pass, zero failures/skips/compiler warnings; `test-2df3eab30fb9497da382a86faf375f04.xcresult`, tests report SHA `09be7beb3445ad4dc0018234f624ab35e222cb0ff4b87043e066911c526fdf93` |
| Hosted watch-cache checks | 15 functions / 25 executions pass on iPhone; separate actual-source Mac run also passes, as recorded above |
| Release iPhone | `build-9902bd52c7644f79a858c6e1fa3117e2.xcresult`: zero errors; two stale removed generated-file cache warnings and the retained watch storyboard deprecation; report SHA `d54cd244ea895a889366ca67dacb71de81da4fc440aa04c30069a0ee2cf5bdef` |
| Release Mac | `build-6055f78dc27149a2842974d2b48980e5.xcresult`: zero errors; two stale removed generated-file cache warnings; report SHA `f210b728312cb8e157089c23834379778961b792c2382494cf31399c42854e5d` |
| Root persistence workflow | All eight phases pass, including actual production opening and malformed-payload refusal; `AdaptivePersistenceWorkflow.log`, SHA `0886ca5631a0379c2f69ab2ebda7480e09071e9ffa14dde9eb5a7d60ac0c9603` |
| Final Swift inventory | 258/258 files parsed, zero gaps/context issues; `.build/Reports/AdaptiveInventory.json`, SHA `50ccfd3bb5128a04f8a7e41a0f57473e5ea4e4a272f9195054e6082cea3593f8` |

Final inventory classifications: 145 production files / 21,500 physical lines; 108 test files / 23,552 lines; five tooling files / 281 lines. Compared with `1e0b3e10`, this checkpoint adds 117 production lines and 581 test lines for the two safety fixes and their diagnostics. These are path classifications, not compiler target membership, logical LOC or proof of safe deletion.

The first current-source iOS Release attempt was stopped after disk exhaustion and is not a passing receipt. An initial Mainboard suite selected Command Line Tools without SwiftParser; its next attempt exhausted disk and could not retain complete results. Obsolete owned derived-data directories and the temporary clean-restore build products were removed, leaving about 19 GiB free before retry. Source, app/account data and `.build/Results` reports were retained. The subsequent iOS Release passed; historical failures remain unchanged. The clean-restore archive retains its committed sources, while its generated products/checkouts are disposable and were removed after their hashes were recorded.

The root persistence task and existing Actions lane now include the actual malformed-payload command. Root TOML and workflow YAML parse successfully. Hosted Actions publication/execution, rendered iPhone/iPad/Mac comparison and physical/signed services remain open.

## Mainboard acceptance

Mainboard commit `7776240c963a766e733d2ada28255e1f151fd541` removes forty source warnings through redundant-conversion/exception cleanup, preserving literal bool/integer/nested query output with twelve regression cases. Strict managed pyrefly 1.4.0 now reports **zero errors and warnings** with unchanged warning severity. Explicit-config scoped Ruff/format and 117 focused cases pass. Root Mainboard declares the missing PyYAML/Seaborn type stubs; its locked install also adds pandas-stubs and advances pglast 6.16→6.17 within its existing bounds. No ignores or weaker settings were introduced.

After the toolchain-selection failure and incomplete disk-full attempt, the separate complete isolated rerun passes **1079 cases, 11 expected skips, three existing warnings**, exit 0 (468.80 pytest seconds). The skips remain three Linux TCP, four offline solver, two setsid and two unconfigured fleet cases. Warnings remain the invalid escape and two Pathspec deprecations. The complete JUnit has 1090 cases, zero failures/errors; `/private/tmp/usagi-mainboard-typed-capacity-rerun/suite.json` SHA is `feb06976e6b729db388055591816218e51f2694b4104db0debb2d5ca89179353`. Strict typing receipt SHA is `a364fcb62c42bfc4a27a389fa5764ea6d2935f0dfa96ac749fdfe29a500b3928`. All 25 Python source hashes stayed unchanged through these runs; the manifest SHA is `47854dd8b96851a4f667e8c3d84ebff6a5e7b70ae93b995f0116bd9b04d3298c`.

The exact declared CUPTI 13.2 wheel's published type metadata confirms the removed integer conversions, including `ActivityKind` as `IntEnum`. It was hash-verified and inspected without installation/import or hardware calls; this establishes the published contract, not CUDA execution on this Mac. The package gate README preserves all receipts and limits. All three Apple workflow references now pin the validated Mainboard commit; it remains unpublished.

## Finish stages 1–4 — October 21

### Source and manual work before final tests

Projects commits `070f3f2a4` and `e55818c5a` implement and test the reusable `dataclass` follow-up. Nonthrowing `@Memberwise` leaves native Codable synthesis available. Default-backed non-Codable fields can use a typed rule's `Value` for generated parameters; the compiler checks the stored default and assignments. The compiled two-field `PendingUploadKey` shape saves three initializer lines. The app keeps native constructors: adding an unpublished macro dependency and a 12 MiB SwiftSyntax checkout for that saving is not justified. No app macro dependency, frozen model or historical decoder changes.

The ownership audit retains weak captures for stored long-lived tasks, callbacks, delegates and continuation termination. Shared cancellation, late-result and account-change tests cover existing boundaries. This is not a proof of every object's deallocation or physical service delivery. Queries remain methods on concrete native models; no new query/storage abstraction or speculative V2/observer rewrite is introduced. Authenticated subject refresh keeps its transactional watermark/full-cache reconciliation. Other collections continue full refresh until incremental reset/deletion semantics and performance justify a change. Their optimization is conditional work, not a correctness requirement to invent another cache now.

Xcode's supported single-target watch conversion moves the SwiftUI app, native application delegate, cache, settings and installed-face migrator under `App/Watch`; WidgetKit lives in `App/Watch/Widgets`. The obsolete storyboard, hosting controller, WatchKit extension target and extension plist are removed. Unrelated converter edits to six schemes, UI-test platform filters and widget identity were restored. App/widget identifiers, app group, widget kind and packet schema remain exact. Final watch build `build-50907aa2561a41b2bff4c83f656b0374` has no compiler/analyzer warnings or errors. The final embedded app has its WidgetKit extension and no obsolete WatchKit extension/storyboard. Physical old-cache and installed-face upgrades are unverified.

Manual isolated checks cover Mac Home/review/settings; iPad lesson group select/clear, interleaving, teaching and rotation; and phone compact review controls. They expose a real accessibility defect: GroupBox's label merged its selection button into a stale custom action. A separate content header now exposes a real button. Progress is one combined accessible value. Subject reading content is capped at 760 points on wide screens. Restoring native Back retains pause/resume separately from explicit End. Fresh iPhone build `build-607ee6afa1ea41c885f12b0055859feb` includes that correction. Earlier captures in `.build/Results/FinishStages-20261021` precede the Back restoration and are labeled by their actual source scope.

Original usability is compared against owner screenshots and pinned `upstream/master` (`d20defc38db78a844d49130031e54969d1907331`) lesson paging/strip and review focus/previous/settings/wrap-up handlers. The original binary is not rebuilt/run. Synthetic Mac native Back → Home → Resume restores the exact unfinished draft. After quitting, the app-control observation unexpectedly relaunched an empty Account window; it was immediately terminated, without connecting, entering a token or using account data. No real exercise or microphone capture was performed. Future quit checks must use the process receipt rather than another app-control observation that can relaunch.

### Actual iPhone simulator disk-full save

`native-store-space-ios` extends the existing Mainboard-owned bounded-volume task and required phone Actions lane. It validates the exact marked private temporary mount, APFS volume name/locality and 64–256 MiB capacity before writing; the actual image is 128 MiB. The fixture writes real bytes down to 4 KiB chunks until `ENOSPC`, never the host volume. Native SwiftData refuses a large note edit on the adopted 38-record store, restores every field/revision/upload attempt, then retries the same expected revision after space is freed. Only the proposed material/revision/pending fields change; no record, schema or unrelated field changes. Two additional test hosts reopen the exact committed state with distinct process identities and the same selector. No production fault hook or model change is added.

The first run's assertion expected only `SQLITE_FULL`; the OS first logs that error, then reports `SQLITE_IOERR_SHMOPEN` when its rollback path cannot grow the shared-memory file on the same full volume. The existing Mac probe already accepts that exact extended code. The renewed assertion permits only those two known codes after confirmed real `ENOSPC`; unrelated errors still fail. The complete three-phase run passes in `FinishStagesIOSSpaceFollowup-20261021.log`, with reports under `.build/Results/StorageSpace.RZKYZK` and exact per-phase `.xcresult` links in its logs. Mainboard ejects the exact image device and removes the successful image. The failed first image is unmounted and retained for diagnosis.

This adds ordinary adopted-store note saving on iPhone Simulator. It does not establish iPhone completed-review/WAL disk-full transactions, all earlier adoption/capture/activation points, physical Data Protection, power loss or interruption inside copy/publication. Those remain unchecked in TASKS.

### Final local gates and external readiness

The tests-last phase follows source/manual checks, without changing the frozen V1 hash `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4` or the three owner edits. Mainboard owns every invocation and retains the result bundles alongside readable reports.

| Current local gate | Receipt and result |
| --- | --- |
| Shared Mac / iPadOS | `FinishStagesSharedMacTests-20261021.log` / `FinishStagesSharedIOSTests-20261021.log`: 576 functions, 887 parameter executions each, zero failures/skips |
| App hosts | `FinishStagesAppIOSTests-20261021.log`: 95 functions/172 executions; `FinishStagesAppMacFinal-20261021.log`: 83/160; one declared separate restart-protocol skip each |
| Dataclass | Projects commit `e55818c5a`; 16 runtime/persistence/macro functions, including five parameterized rejected declarations, pass after manual/compiler work |
| iPhone native UI subset | `FinishStagesPhoneUI*` and `FinishStagesPhoneRootUI*`, with `FinishStagesPhoneSettingsFinal-20261021.log` completing the root Settings route. Failed/interrupted attempts retain their exact outcomes; broader regression work is recorded separately |
| iPhone restart | `FinishStagesNativeRestart-20261021.log`: all 12 phases complete, eight ordinary passes and four exact exit-86 producers; final consumer verifies 39 exact records and one penalized pending answer |
| Bounded Mac / iPhone ENOSPC | Ten Mac receipts in `StorageSpace.qVvN7e`; three iPhone save/reopen phases in `StorageSpace.RZKYZK`; successful images ejected and removed |
| Independent historical values | `FinishStagesHistoricalV1-20261021.log`, `FrozenValues.1r6VVZ`: frozen writer/reader compilation, two exact fresh-process reads and source-integrity controls |
| Parser / style | `FinishStagesSwiftParseFinal-20261021.log`: 446 configured Swift files parse. `FinishStagesSwiftLint-20261021.log`: 252 files; `FinishStagesActiveSourceLint-20261021.log`: 173 files, no rewrites/failures. Later test-only harness edits receive a separate formatter/compiler check |
| Release / package policy | iOS `build-b22db5d2f97449ecb6b9561c1fa8f285`, Mac `build-efba0c89669349638384a04dfae6740d`; zero native compiler/analyzer errors/warnings. Both `FinishStagesRelease*Audit-20261021.log` reports pass with no violations across three iOS executable paths and one Mac path; retired libraries/test stores/test bundles are absent and localized names/icon/microphone metadata satisfy the policy |

The broader phone run exposes older scroll-harness assumptions on Home: a scroll container need not itself be a tappable accessibility element, and a clipped row can still report `isHittable`. Tests must scroll inside the content viewport and avoid the floating tab bar before tapping. The initial broad attempt is explicitly interrupted to repair the harness; its partial results are not a complete suite pass. Settings Back queries now use the real native Back identifier rather than matching the underlying Home Settings button. Anki menu dismissal targets the passive visible count row outside the popover rather than the oversized navigation-bar accessibility frame, which could accidentally tap a grading action.

The former Reduce Motion placeholder is replaced with the real two-subject combined-Anki fixture and all existing feedback/milestone/settings assertions. The UI test reads Apple's public [system Reduce Motion status](https://developer.apple.com/documentation/uikit/uiaccessibility/isreducemotionenabled); its UIKit import is test-only, not another production UI bridge. An unconfigured device produces an explicit precondition skip before app launch, and the accessibility acceptance gate remains open. No system preference is changed and a skipped case is never recorded as verified Reduced Motion behavior.

Later UI attempts expose a separate automation delay: the catalog and landscape assertions finish, but app termination after the test method costs about 120 seconds. Both asynchronous cleanup and the documented synchronous callback reproduce the delay; the synchronous attempt records two passing case bodies but times out before producing a complete readable result bundle. Those attempts are not accepted suite passes. The final harness keeps explicit method-local `defer` lifetimes, as the passing root-flow suite does, removes the duplicate shared cleanup and global orientation handlers, and restores rotation before closing the fixture. This deliberately retains necessary resource-lifetime lines. The current probe and any further full-suite result must be recorded before claiming the broader gate complete. A Mac lock-state clarification is pending; no locked-state assumption or global setting change is made.

The explicit-lifetime probe (`FinishStagesExplicitLifetime-20261021.log`) still reports a 142-second passing catalog case, then reaches its 360-second bound without finalizing a readable result bundle. The delay therefore persists across cleanup styles; it is not accepted as a fixed code defect or a complete UI gate. Mac UI automation separately times out enabling automation before app launch. The complete local source/unit/storage/Release results above remain valid in their stated scopes, while the broader 50-case phone run, five separately driven URL cases and wider iPad/Mac UI gates remain open. No test job is left running.

A host check finds 5.4 GiB free and 99% usage on the data volume. With no workspace build running, only rebuildable compiler intermediates and indexes from the completed app/shared builds are pruned. Free space rises to 8.7 GiB; source, build products, frozen inputs, result bundles, readable reports and screenshots are retained. Disk pressure and the pending lock-state check are environment observations, not established explanations of the UI delay.

The project explicitly uses Xcode 27.0 / Swift 6.4 and its builds resolve the full Xcode toolchain. The machine's global `xcode-select` still points to CommandLineTools; some UI-runner logs report that an internal `xcrun simctl` lookup fails. These are observations, not proof of the delay's cause. The global selection remains unchanged. The workflow's `xcode-27` label and `/Applications/Xcode_27.app` match GitHub's current documented preview image and Xcode 27.0 build `27A266a`; runner availability is verified, but hosted execution still requires the unpublished Mainboard pin. [GitHub image definition](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), [preview announcement](https://github.com/actions/runner-images/issues/14404).

| External or broader gate | Concrete remaining requirement |
| --- | --- |
| iCloud | Register `iCloud.com.pedrexus.usagiunagi` under the owner's team, inspect signed entitlements and verify two-device edit/deferral/account-change delivery with WaniKani still authoritative |
| App identity / Keychain | iOS retains `com.davidsansome.wanikani`, Mac retains `com.pedrexus.tsurukame.mac`; current signing settings still contain the original iOS team. A fork-owned signed identity/upgrade path needs explicit owner configuration and original-install access; unsigned builds establish no Keychain continuity |
| Paired Watch | App `com.davidsansome.wanikani.watchapp`, widget `com.davidsansome.wanikani.watchapp.c.widgets`, group `group.com.pedrexus.usagiunagi.watch`; prove signed group/cache and installed-face continuity plus background packet delivery on a paired device |
| Physical / full usability | Real microphone/recognition and IME composition/caret/audio/background behavior; full iPad/Mac and normal-launch/window-restoration checks, largest-text Home, VoiceOver/contrast/Reduce Motion and icon/device acceptance |
| Storage / statistics | Remaining iPhone review/WAL/early-adoption ENOSPC and physical interruption/Data Protection/power-loss cases; permitted complete-catalog performance measurements and honest exam-readiness calibration |
| Hosted Actions | All four checkouts pin `b72cd6fdd7870842a0cd5a7517231d26e5123eff`; `FinishStagesMainboardPin-20261021.log` records HTTP 422 “No commit found.” Publication/push is not authorized, so no hosted success is claimed |

No PR, push, signing or distribution is performed. iPhone Duo remains deferred, Parquet remains retired and the dismissed Coverage popup is not reopened. The broader modernization goal remains active.

## iPhone navigation and refresh audit follow-up

The warm-link task now finishes with a readable passing result bundle:
`test-57dd5234d5ad40fdb8f08e816d7526bb.xcresult` (one test, no failures,
skips, runtime warnings or compiler/analyzer warnings). Mainboard delivers the actual
review, lesson and subject URLs to the isolated fixture app. The test verifies that
Settings and a queued subject link preserve a typed review draft, and closing each
study/detail route returns to Stats. This run uses `c81eb0a2`; no navigation source change
is required. `NavigationFinish-WarmLinks-20261021.log` retains the complete verdict.

The next two-test run produces a readable failed suite, rather than an incomplete result:
`test-1a52b91392874b988c17a51bc3c2a094.xcresult`. The lesson quiz passes its wrong-answer,
completion and next-batch assertions. Its old final expectation incorrectly disabled
the batch button when no individual items were selected despite other available lessons.
The renewed assertion checks `0 selected`, the enabled `Start a batch` action and opening
the next teaching page. It retains the completed-subject removal and grading assertions.
This individual pass does not make the two-test suite green.

The refresh case fails on a stale accessibility element type. Its exported screenshot
shows the real sync indicator above the cached Home content; the hierarchy assigns
`app.syncProgress` to an ActivityIndicator container, with an unnamed ProgressIndicator
inside. The test now queries the identifier without assuming that container type, and
keeps every visibility, label, interactivity and completion assertion. The root also
initially observes `model.isSyncing`, so a scene created during an existing sync receives
the current progress state. No additional observation abstraction or schema change is
introduced. A newly created Mac window during sync is still a separate rendered gate.

The focused refresh retry passes and finalizes:
`test-8ff97312e0d9432e84fa78e504910ec2.xcresult` (one test, no failures, skips,
runtime warnings or compiler/analyzer warnings). Cached content and Settings remain
usable during the held refresh; background/foreground preserves the indicator; the
explicit fixture URL releases the refresh; the learned count changes from 864 to 865
and the refresh action becomes available again. `NavigationFinish-RefreshFinal-20261021.log`
is authoritative. The changed shared source also passes all 577 Mac test functions
across four targets (`NavigationFinish-SharedMac-20261021.log`).

The fresh complete lint run exits 1 with the same 30 formatter diagnostics in the two
protected owner-edited files; it scans 447 files, rewrites none and reports no other
failed step. The full analysis inventory still reports 230 findings from 98 rules.
`NavigationFinish-FullLint-20261021.log` and `NavigationFinish-AllRules-20261021.log`
retain these non-green results. The three protected file hashes remain unchanged.

The three note-conflict URL cases initially finalize as three failures, all before any
conflict event is requested (`test-a2be0008804f4b9196ddffc545e45871.xcresult`,
`NavigationFinish-MaterialConflicts-20261021.log`). The shared helper taps the submit
button using stale pre-keyboard geometry. In the rejected-commit case, the native
synthesized-event archive records `(356, 747)`, while the captured hierarchy places the
button at `(322, 451, 68, 58)` above the keyboard. A direct read-only simulator screenshot
also shows the unchanged typed answer. No conflict/grading pass is inferred from this
failure. The helper now verifies the typed value and waits for a hittable button outside
the keyboard frame before its single ordinary tap; it adds no timed sleep, retry tap or
weakened grading assertion. The renewed two-file parser/UI/formatter/SwiftLint check
passes (`NavigationFinish-SourceLint-20261022.log`). The incomplete early attachment
export is recorded separately; the final export succeeds under
`NavigationFinish-ConflictFailure-20261022/`.

The three conflict cases and broader phone/iPad/Mac acceptance remain open at this
checkpoint. The existing 120-second test/finalization delays remain observable;
these completed bounded runs do not establish their cause or resolve the full UI suite.
Only explicit memory-only fixtures are launched; no real account, exercises, microphone,
normal-account window restoration, signed service or publication is used.

The geometry-aware helper's focused replacement test then passes and finalizes as
`test-6a9f0f572f8c462faa390a8caa50419b.xcresult`. Mainboard delivers the actual armed
conflict URL, and all draft, explicit-replacement, hidden-reading and exclusion assertions
pass. Its final report nevertheless contains one runtime warning, `Invalid frame
dimension (negative or non-finite)`, when the notes keyboard opens. A successful test
boolean alone is not a warning-free acceptance result. The raw native issue summary
provides no source location; it is retained in
`.build/Reports/NavigationFinish-ConflictRawResult-20261022.json`.

The review screen supplies its raw viewport height as a minimum frame height. The
follow-up bounds that value at zero during keyboard/presentation transitions. This is
the suspected layout boundary, not a source location supplied by XCTest. The pending
negative-only run is deliberately canceled before its first case begins so all three
cases can rerun together against the bound. It exits 75 with a canceled-runner failure
(`test-0a3344c5d36748ccbd036bfb4a84b176.xcresult`), not an app failure or accepted test
run. Its process exits normally after cancellation; no fixture app remains running.
All three changed Swift files pass the renewed parser/UI/formatter/SwiftLint checks.

The current unsigned Mac Release build also passes with zero compiler/analyzer warnings
or errors: `build-e4cf0075006a4e74a13d5d6c379d2c48.xcresult`, recorded in
`NavigationFinish-ReleaseMac-20261022.log`. The renewed bundle policy passes its one
packaged executable and localized names with no violations
(`.build/Reports/NavigationFinish-ReleaseMacBundle-20261022.json`). This covers the
endpoint validation and initial sync-observation source changes; it does not establish
signed-service, normal-launch or rendered Mac acceptance.

### Final behavior results and retained warning — October 22

The combined conflict run finalizes as `test-e6931c8fe32c484fbbd201e88743b430.xcresult`:
three passed, no failures or skips, and **three runtime frame warnings**. All five allowed
URLs are actually delivered, including separate requests to the same token for the
unarmed and missing-token scenarios. Rejected commits are not acknowledged; mismatched
events do not alter notes; explicit replacement retains the draft, hidden reading note
and exclusion state. The viewport bound does not remove the warning and is reverted.
`ReviewScreen.swift` has no change from the parent commit.

The editor instead adopts Apple's standard [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)
and a keyboard `ToolbarItem`, retaining the Done action/identifier and using no platform
branch. The installed Xcode 27 interface confirms its default flexible sizing. This is
a native toolbar cleanup, **not a claimed warning fix**: the final focused replacement
case repeats the warning. The native issue summary gives no source location; the Apple
forum retrieval supplies a verification page rather than usable diagnostic evidence.
Do not attribute the warning to Apple's implementation or another app source line
without further evidence. Its current reproducer is isolated review → incorrect meaning
→ Reveal → Notes and synonyms → focus Meaning note. A minimal reproduction/source trace
is still needed. No layout warning is silenced or filtered from the reports.

| Final check | Receipt and exact scope |
| --- | --- |
| Final editor UI | `test-a94f4a0df70f4891a8e3dd917a513aa7.xcresult` / `NavigationFinish-ToolbarFinal-20261022.log`: one passed, no failures or skips, one retained frame warning; explicit conflict URL delivered, zero compiler/analyzer warnings/errors |
| Shared Mac source | `NavigationFinish-SharedMacFinal-20261022.log`: 577 functions across four targets pass |
| iOS Release | `build-8827992505df49c2938779a1f20d0183.xcresult`: zero compiler/analyzer errors or warnings |
| Mac Release | `build-d64aa5eef42846d1acb867f57c265bad.xcresult`: zero compiler/analyzer errors or warnings |
| Release bundles | `NavigationFinish-ReleaseIOSBundleFinal-20261022.json` / `NavigationFinish-ReleaseMacBundleToolbar-20261022.json` under `.build/Reports/`: three iOS/watch/widget executables and one Mac executable, zero policy violations |
| Changed Swift | `NavigationFinish-SourceLintFinal-20261022.log`: three files pass parser/UI rules, strict formatting and SwiftLint, no rewrites |
| Whole lint / analysis | `NavigationFinish-FullLintFinal-20261022.log`: 447 files, no rewrites, only the same 30 protected-file formatter diagnostics; `NavigationFinish-AllRulesFinal-20261022.log`: 230 findings from 98 rules, inventory only |
| Hosted prerequisite | `NavigationFinish-MainboardPin-20261022.log`: current `b34c931` pin still returns HTTP 422; no publication is authorized |

The final focused toolbar result finishes exporting and exits 0; its warning stays open.
The negative behavior cases above precede the spacing-only editor change; they are not
presented as rerun against that change. Warm links and held refresh retain their earlier
source scopes. The broader phone/iPad/Mac, newly opened Mac scene during sync, accessibility,
IME/physical voice/storage and signed-service gates remain open. Native teardown/export
delays and internal diagnostic `simctl` lookup failures remain unexplained. The original
account app is never launched; only explicit memory-only fixtures are used. No PR, push,
signing or distribution occurs, and the overall modernization goal remains active.
All native jobs are terminal, no fixture process remains running, the three protected
owner edits retain their original hashes, and the frozen V1 schema SHA remains
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.

## Notes keyboard diagnostic follow-up — October 22

The full native case summary contains 64 call-stack records, all with address zero and
no symbol/location. Xcode's session log reports successful symbolication, but the stored
frames cannot identify a source line. `NotesWarning-CaseSummary-20261022.json` and
`NotesWarning-TestDetails-20261022.json` under `.build/Reports/`, plus the exported
`NotesWarning-Diagnostics-20261022/`, retain that limit. The app's standard error contains
several occurrences while XCTest reports one warning; warning counts are not occurrence
counts.

The existing lesson-notes test reproduces the warning before the quiz/review view exists,
then saves and reopens the exact note and synonym. Its quiz step fails because the native
tap archive targets `(356, 687)` while the captured video shows the submit button above
the keyboard (`test-e52eea12a6ac443a80a698bcf8e7359c.xcresult`,
`NotesWarning-LessonEditor-20261022.log`, `NotesWarning-LessonFailure-20261022/`). This is
a failed test, not accepted synonym grading. The existing readiness predicate is moved
to one test helper and reused here; typed-value, reading-transition and conflict checks
remain intact. The renewed helper passes parser/UI/formatter/SwiftLint checks.

Mainboard compiles a standalone 56-line SwiftUI app against the installed iOS 27 simulator
SDK, with no app module or persistence dependency. It uses `NavigationStack`, `Form`,
`TextEditor`, a constant positive minimum height, focus state and optional public keyboard
toolbar items. Every launch requires `--review-fixture`. Source/plist and binary hash are
retained as `NotesWarning-Probe-20261022.*` / `NotesWarning-ProbeBinary-20261022.sha256`
under `.build/Reports/`. Explicit `SDKROOT`, `xcrun --sdk iphonesimulator` and the Swift
`-sdk`/simulator target are needed for the standalone cross-compile; the initial inherited
Mac sysroot warning is retained, then a clean rebuild precedes installation. No signing
command is used.

| Standalone process | Confirmed rendered condition | Frame warnings in unified log |
| --- | --- | --- |
| 18845 | Direct form, keyboard visible, no toolbar | 0 |
| 19244 | Initial sheet probe without keyboard focus | Inconclusive; not a passing keyboard check |
| 20401 | Corrected sheet form, keyboard and caret visible, no toolbar | 0 |
| 20698 | Sheet form with native keyboard toolbar and spacer | 1 |
| 21758 | Same sheet toolbar with spacer removed | 1 |
| 22204 | Direct form with one keyboard-toolbar button, no sheet or spacer | 1 |

`NotesWarning-ProbeFinalUnifiedLog-20261022.json` retains 3,964 records from exactly those
six process IDs. The warnings originate from `com.apple.runtime-issues` / `SwiftUI`, with
SwiftUICore/SwiftUI image UUIDs and frame offsets in the log backtrace. Screenshots and
launch/stop logs use the corresponding `NotesWarning-Probe*` names in `.build/Results/`.
The minimal public keyboard-toolbar pattern therefore reproduces the warning on this
simulator independently of usagiunagi's layout, grading and storage. This is a scoped
framework reproduction, not proof of physical-device behavior or an Apple-confirmed fix.
The native control remains functional and no diagnostic is suppressed. The temporary
app is terminated and uninstalled; temporary sources/binary are removed after preserving
the receipts. The probe adds no flag, dependency or helper library to the app.

### Review detail access

The first three-case regression finalizes as
`test-8052f6b6e60b4c2985900a4ce2a8e0f1.xcresult`: lesson notes/synonym grading and explicit
conflict replacement pass; the privacy case fails. It is not a passing suite. The failed
hierarchy still contains All information at `y = 870.7` in an 874-point window, behind the
fixed review controls; the action has not opened the reading content. The explanation
itself also belongs to `SubjectDetailsContent`'s lazy stack. The export is retained in
`NotesWarning-RegressionFailure-20261022/`.

All information moves into the existing fixed 44-point review tool strip, using the same
SF Symbol, action and Space shortcut. It remains conditional on revealed details and
the existing `canShowAll` permission. No grading, store, visibility or platform branch
changes. The privacy test now checks the real toolbar control is hittable before its
ordinary tap, then uses the existing scroll helper to check the lazy reading explanation.
The unanswered reading/note and hidden/revealed English assertions stay intact.

Both changed Swift files pass parser/UI rules, strict formatting and SwiftLint in
`NotesWarning-ReviewControlsLint-20261022.log`. Post-change Release builds
`build-67f5ba27350c408eb888ad2f1a514481.xcresult` (iOS) and
`build-a9c66386fdf94e4fb08470c2ee7e4292.xcresult` (Mac) pass with zero compiler/analyzer
errors or warnings. `NotesWarning-ReleaseIOSBundle-20261022.json` /
`NotesWarning-ReleaseMacBundle-20261022.json` audit three iOS/watch/widget executables and
one Mac executable with zero violations. All 577 shared Mac functions pass again in
`NotesWarning-SharedMac-20261022.log`. These builds precede the accessibility-group change
below; final-source verification is recorded separately. The known native keyboard-toolbar
warning remains visible rather than suppressed.

The next three-case run, `test-42a06e34a0cc467caf60a7fd5efcba42.xcresult`, also retains
two passes and one failure: the new info control reveals reading content, but the
translation tap does not reveal English. Its hierarchy places Show translation at
`y = 760.7` behind the fixed controls, while `review.scroll`'s accessibility frame still
extends through that covered region. `isHittable` alone is insufficient here. The export
is retained in `NotesWarning-TranslationFailure-20261022/`; this is not recorded as a
passing suite.

The fixed footer is now a named Study controls accessibility group with its own
`review.controls` frame. The existing scroll helper requires the complete target to be
above that frame, except while the material form or standalone subject page owns the
interaction. It retains the tab-bar exclusion and every existing assertion. No repeat
tap, sleep or diagnostic filter is added.

### Final-source verification

`test-662231196cdc491c92c048e90d57bd34.xcresult` finalizes successfully with two passes,
zero failures or skips, zero compiler/analyzer warnings and the one retained keyboard
runtime warning (`NotesWarning-ControlsFinal-20261022.log`). The conflict case verifies
the exact draft replacement and retained concealed note/exclusion after actual fixture
URL delivery. The privacy case verifies reading explanation/note concealment, explicit
information access, and English concealment followed by its explicit reveal. The final
source hashes are in `NotesWarning-ControlsSource-20261022.sha256`. The exported screenshot
in `NotesWarning-ControlsCapture-20261022/` is inspected; it shows the revealed context
sentence above the fixed controls. The lesson-note/custom-synonym quiz case already passed
in both preceding three-case trials; those whole suites remain recorded as failures.

The same source passes all 577 shared Mac functions in
`NotesWarning-SharedMacFinal-20261022.log`. Final unsigned Release builds are
`build-89f5903a6b0c49b58747421f59d86748.xcresult` (iOS) and
`build-385a7ed89ac24806ba162ab376c72416.xcresult` (Mac), with zero compiler/analyzer errors
or warnings. `NotesWarning-ReleaseIOSBundleFinal-20261022.json` and
`NotesWarning-ReleaseMacBundleFinal-20261022.json` audit three iOS/watch/widget executables
and one Mac executable with zero violations.

`NotesWarning-FinalFullLint-20261022.log` checks 447 files without rewriting any. It still
fails only the same 30 formatter diagnostics in the two protected owner-edited files.
The owner-file hashes remain unchanged. `NotesWarning-FinalAllRules-20261022.log` retains
230 findings from 98 rules; inventory exit 0 is not a passing lint gate. Scoped checks of
both changed Swift files pass. No migration signal, assertion or runtime issue is hidden.
Broader UI/accessibility, physical services and signed acceptance stay open.

### Bounded test-diagnostics experiment

The installed Xcode help documents `-collect-test-diagnostics on-failure|never`
(`NotesWarning-XcodebuildHelp-20261022.txt`). Mainboard already passes native arguments
through its existing `--setting` option, so no new workflow helper or setting is added.
One unchanged-source positive conflict case runs with
`--setting=-collect-test-diagnostics --setting=never`, retaining actual URL delivery,
every assertion and runtime-issue reporting.

`test-a8d4ca2a29174754abcd98049cf8c552.xcresult` finalizes successfully: one pass, zero
failures/skips, zero compiler/analyzer warnings and the same runtime warning
(`NotesWarning-DiagnosticsPolicy-20261022.log`). The case takes 160.009 seconds versus
160.006 in the preceding final-source run; its body reaches teardown at 37.98 seconds.
The native action takes 419.048 seconds including startup/finalization. This single
measurement finds no useful reduction in the repeated teardown delay and does not
establish its cause. App, Mainboard and CI diagnostic defaults remain unchanged.

## Native accessibility audit — October 22

The installed Xcode 27 `XCUIAutomation` header and Swift interface document
`performAccessibilityAudit()` as the current-view audit, defaulting to `.all`. Each
returned issue records an XCTest failure; an optional handler can suppress it. The new
tests use the default full scope with no handler. No system accessibility preference,
account or microphone state is changed.

Three isolated iPhone tests cover Home's action viewport and level-progress viewport,
the lesson picker and a selected teaching page, and review answering plus revealed
details. They reuse existing fixture launches and navigation. Source hashes are retained
in `.build/Reports/Accessibility-AuditSource-20261022.sha256`; scoped parser/UI rules,
strict formatting and SwiftLint pass in `Accessibility-AuditLint-20261022.log`.
`Accessibility-AuditInitial-20261022.log` finalizes as
`test-2997b2dd2393432c9329a39f7852c8fa.xcresult`: all three cases fail, with 74 recorded
failures and no compiler/analyzer or reported runtime warnings. This is discovery
evidence, not passing accessibility acceptance. These automated checks do not replace
a physical VoiceOver walkthrough or complete the wider visual/keyboard/device gates.

The export in `Accessibility-AuditInitialCapture-20261022/` retains full issue descriptions,
element/app screenshots and recordings. Detailed case trees are in
`.build/Reports/Accessibility-HomeDetails-20261022.json` and
`Accessibility-LessonDetails-20261022.json`. Findings comprise 29 partial Dynamic Type,
one unsupported Dynamic Type, 26 near-threshold contrast, 12 contrast failures, three
clipping reports, two hit-region reports and one failed test assertion. These counts
are issues across three cases, not 74 distinct application defects.

The Home test mistakenly queries its combined level-progress row as a button; the existing
regression correctly uses the general accessibility-element query. Its second audit
therefore runs at the wrong viewport after the failed scroll. Captures also show a
fully visible `1/1` lesson indicator despite a clipping report, and contrast targets
behind the native floating tab bar. The fixed-size system font in the subject header
and redundant thin review progress indicator are separate actionable findings. Remaining
reports on semantic SwiftUI fonts need an independent control before layout workarounds.

### Independent native control and focused changes

Mainboard cross-compiles a 25-line standalone SwiftUI app containing only a native form,
semantic body/headline/secondary text, labeled content and a glass button. The explicit
fixture argument and unique `dev.usagiunagi.accessibility-probe` identifier isolate it
from account services. Source/plist, binary hash and test driver are retained under
`.build/Reports/Accessibility-Probe*20261022*`. The full audit finalizes as
`test-24e2beade97a44058baafec7b26cadc3.xcresult`: one failed case with three near-threshold
contrast issues, on the standard section header, secondary text and glass button.
There is no Dynamic Type failure or reported runtime warning. The exported light-mode
capture is inspected. This is a scoped native control, not a claim that every application
contrast or font finding is a framework defect. The app is terminated/uninstalled and
its temporary binary directory is removed.

The subject header now uses native scaled metrics for its system font and image height,
and the matching relative text style for custom fonts. Long subject text can wrap instead
of shrinking back into one line. Home action cards request their full vertical content
height. Account-level and subject-section text inherit the primary style; the compact
lesson counter keeps its intrinsic width. The thin review progress bar remains visible
but leaves the accessibility tree because the combined row already announces exact
completed/remaining counts and accuracy. No action or saved information is removed.

The exploratory full audits and standalone test driver are retained as diagnostic source
receipts, without adding a failing broad audit to the default regression suite or filtering
its recorded issues. Full accessibility acceptance remains open. Stable native regressions
instead check largest-text Home review/catalog navigation, actual lesson-heading height
growth and long-vocabulary wrapping, lesson-footer access, and the full native hit-region
audit of largest-text review controls. Scoped checks of all six changed Swift files pass
in `Accessibility-FixesLintFinal-20261022.log`; final source hashes are in
`Accessibility-FixesSource-20261022.sha256`. The initial focused native run in
`Accessibility-LargestType-20261022.log` is retained as the failed trial below.

The largest-text trial completes Home review/return and level-catalog navigation, then
stops the lesson comparison before its second heading check. Its default-size vocabulary
page is captured, but at the largest size the helper waits for an offscreen Choose lessons
row instead of scrolling Home. A read-only native capture while the fixture process is
confirmed live (`Accessibility-LessonFailureLive-20261022.png`) shows that Home did launch.
This failed helper is not accepted scaling evidence. The fixed account header also
occupies substantial space with large/long text; its scrolling/presentation needs a
separate usability follow-up. The complete trial finalizes as
`test-6b4984dd2fcd49a0af6aa90e5355cc00.xcresult`: Home navigation and the largest-text
review hit-region audit pass; the lesson helper fails. There are no compiler/analyzer
or reported runtime warnings. This is not a passing combined suite.

The lesson-only retry (`test-4c8dd89cb0b74909884c33ee43337af2.xcresult`) correctly scrolls
Home, then fails reaching the final vocabulary tile. Its captured picker has an
accessibility scroll frame extending from `y = 227.3` through the bottom of the window,
including the large fixed controls. The fallback swipes the window rather than the
visible list. `Accessibility-LessonRetryCapture-20261022/` preserves the real failure
hierarchy and screenshot; no heading-growth assertion has passed in this trial.

The picker now names its existing list and Lesson controls accessibility group. The
existing scroll helper selects the relevant named scroll surface, clips drag coordinates
above fixed controls, and avoids accepting targets covered by either study footer. No
extra application scrolling abstraction, platform branch, retry tap or diagnostic filter
is added. Scoped checks pass in `Accessibility-ViewportLintFinal-20261022.log`. Source
hashes are in `Accessibility-ViewportSource-20261022.sha256`; the bounded heading/privacy
rerun in `Accessibility-ViewportFinal-20261022.log` finalizes as recorded below.

Inspected largest-text captures also keep two usability failures open: fixed account
identity occupies too much of Home, and focusing an answer can scroll the Japanese
question outside the visible review area. The fixture-only notice magnifies the former,
but does not justify treating the production identity layout as accepted. The next
correction should place account context in scrolling Home content and keep the current
question visible with the answer/keyboard, preserving the compact normal-size flow,
hidden readings, pause and grading. A passing hit-region audit alone proves neither.

### Final scoped evidence

`test-990b0e617842427698df445b5628eb91.xcresult` finalizes successfully: the renewed lesson
comparison and review-privacy case both pass, with zero failures/skips, compiler/analyzer
warnings or reported runtime warnings. The unchanged-source receipt is
`Accessibility-ViewportSource-20261022.sha256`. Exports in
`Accessibility-ViewportCapture-20261022/` are inspected. The measured greeting height is
57.333 points at the default category and 191 points at accessibility XXXL, with all five
characters visible across two lines. The footer's Quiz action remains reachable; the
primary Start quiz button is visible. The default-size view retains its compact header.
The privacy case keeps unanswered reading content concealed until All information and
keeps English concealed until Show translation. These two passes do not erase either
failed trial or establish full accessibility acceptance.

All 577 shared Mac test functions pass in `Accessibility-SharedMac-20261022.log`.
Final Release builds `build-fe73542425ad42128382c1c65899ec69.xcresult` (Mac) and
`build-ae55071a58ab447abed9e90c160ddb4c.xcresult` (iOS) pass with zero compiler/analyzer
errors or warnings. `Accessibility-ReleaseMacBundle-20261022.json` and
`Accessibility-ReleaseIOSBundle-20261022.json` audit one Mac and three iOS/watch/widget
executables with zero violations.
The fresh complete lint still checks 447 files
without rewriting any and fails only the same 30 protected formatter diagnostics
(`Accessibility-FinalFullLint-20261022.log`). The full rule inventory remains 230 findings
from 98 rules (`Accessibility-FinalAllRules-20261022.log`). The three owner-file hashes
and frozen V1 schema remain unchanged.

`Accessibility-MainboardPin-20261022.log` rechecks GitHub: the pinned Mainboard `b34c931`
still returns HTTP 422, No commit found. All five workflow checkouts use the same pin;
no hosted execution, publication, signing or distribution is claimed. No probe app or
binary is left installed, and no application dependency or platform check is introduced.
