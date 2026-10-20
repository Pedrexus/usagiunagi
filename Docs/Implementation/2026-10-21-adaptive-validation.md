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
