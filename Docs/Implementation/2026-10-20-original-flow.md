# Original study-flow comparison

Source comparison after `d90afc63` against pinned original `upstream/master` at `d20defc38db78a844d49130031e54969d1907331`. This original already contains its Orizuru visual refresh. The first comparison covers shared Home, lesson teaching/picker/quiz, typed and Anki reviews, feedback/correction, summaries, catalog/search, details and settings at source level. The scoped rendered Mac follow-up below does not establish full cross-platform usability.

The existing compact Home sections, subject colors, lesson strip/quiz, native settings, grading and saved-work responsibilities remain. The source comparison identified these concrete regressions and the following production fixes:

| Original behavior | Shared implementation correction |
| --- | --- |
| `LessonsViewController` Space/J plays the visible teaching subject | `LessonFlowView` requires a page-index audio callback. `NativeLessonView` retains the catalog values it already loaded and calls the existing audio toggle for that page. No additional fetch, task, resolver or autoplay is introduced. The quiz keeps its own keyboard handling. |
| `ReviewViewController` freezes an incorrect answer until explicit Backspace/retry; Return continues | `StudyAnswerInput` receives the existing phase's edit permission. The iOS delegate rejects replacement while retaining keyboard/Return handling; deletion explicitly retries. The native Mac field disables editing while Continue remains the default Return action and Delete invokes Try again. Katakana uses the same input behavior. |
| `ReviewSummaryViewController` Return dismisses results | Both native review and Katakana summary Done buttons use the default action. |
| Original results distinguish missed items at the account's current level | `NativeReviewState` includes the verified account projection's current level and passes it to the existing summary. This transient Sendable property is not a stored model/payload change. |
| Original search always shows meanings/readings, independently of catalog concealment | Search rows always show answers without modifying the stored catalog preference; other catalog modes retain concealment. Accessibility text follows the same visibility. |
| `SubjectCatalogueViewController` updates its title when changing level | The shared level title derives from the same current query as its results, including picker/swipe changes. The remaining-items title keeps its original behavior. |
| Home supports Return, Command-L and Command-R | Enabled shared lesson/review buttons own Command-L/R. Home Return selects reviews first, otherwise available lessons. Inactive Home controls are disabled behind another tab/destination or settings. Mac's global refresh moves to Command-Shift-R to avoid the restored review command. |
| Subject details apply the saved Japanese size preference | The existing header receives the same bounded font scale used in reviews. Its current 72-point baseline and responsive single-line fitting remain; no device-idiom layout branch is added. |

Statistics now reuse Home's existing five SRS colors through `StudyPalette.color(for:)` and the existing `StudySRSCategory` names/stage classification. This removes the separate Home color array and the statistics chart's four identical purple bars; counts, labels and layout retain their responsibilities. The forecast is a private computed view in the same Home file to keep SwiftUI's type checking bounded; no component type or navigation/service layer is added.

Intentional existing native adaptations remain: Command-C/A preserve Copy/Select All; correction uses Control-C/A. Font actions preserve ordinary Tab/arrow focus and caret behavior. SwiftUI navigation/glass/system typography, inline statistics sources/coverage and native forms remain. Subject colors match the reference's light-mode identities; dark-mode contrast and larger-text layouts still need rendered inspection. No new color scheme or typeface is introduced.

## Final acceptance still required

Repair old test launchers before running them; retired flags must never fall through to a production account. Use explicit native fixture launches with fake speech/audio, preserving old assertions and frozen store fixtures. Complete rendered iPhone/iPad/Mac comparison and the final test stage:

- Home Return priority/disabled/vacation/zero-work cases, Command-L/R and Mac refresh; no shortcut activity behind settings, another tab or destination; focus returns after navigation/sheets.
- Wrong-answer type/paste/cut rejection, soft/hardware Return continuation, Delete/Try again unlock, Japanese marked text/caret and draft restoration; typed/Anki/Katakana paths remain separate where required.
- Lesson Space/J targets the visible subject, skips quiz interception and respects audio/voice ownership; no extra lesson autoplay.
- Both summary Return actions, completed-subject accuracy/current-level grouping and missed-item navigation.
- Search after hiding catalog answers, unchanged preference after returning, title changes from both paging controls and swipes, and detail font-size changes at compact/wide sizes.
- Statistics stage counts/labels/colors, pending/refresh/vacation states, accessibility and contrast; coverage/pace remain study measures rather than exam passing probabilities.

All broader migration, synchronization, speech/device and final Release/dependency gates remain in [TASKS](../TASKS.md) and [the migration specification](../Migration.md).

## Compiler and source evidence

Mainboard `ce366957`, Xcode 27/Swift 6.4: canonical Debug app builds pass for native Mac and generic iOS Simulator, using the same separate derived-data/signing-disabled/pinned-plugin recipes as the [store-opening checkpoint](2026-10-20-native-store-opening.md). Both native summaries contain zero errors/warnings. The separate no-AppIntents metadata message and earlier fresh watch-host warning remain scoped as before. Initial attempts caught an incorrect key-handler overload; the corrected code and smaller Home forecast expression compile on both platforms. No app, store, test or benchmark ran for this compiler checkpoint; the later manual scope follows below.

All fifteen changed Swift files pass formatting and strict SwiftLint without rewrites. Mainboard inventory parses 266/266 files, without context issues or gaps: 145 production files/21,224 physical lines, 116 test files/23,717 lines and five tooling files/282 lines. The production increase of 51 lines restores behavior and shared typing; it is not a LOC reduction or measured speed claim. V1 remains SHA-256 `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.

| Frozen evidence | SHA-256 |
| --- | --- |
| `.build/Results/build-0d01a95306dd4c228d3ad1dadc7fbf15.build.json` (Mac) | `926468b67dc6f406a39ba6c2982418660212a3673bf4c3b46a4f4df6efba1445` |
| `.build/Results/build-fd13422e4e4547b69cd1c6bab26ff3de.build.json` (iOS Simulator) | `e37f31f3cba1d95fdf00535310e782d6d858785e28794993e297bac98e038a1a` |
| `.build/Reports/OriginalFlowInventory.json` | `5958af1a80f8834f429758692216d68e587d214d9503698051e691d7973a1035` |
| `.build/Reports/OriginalFlowComparison.json` | `1632dda117b3d1f74712da44411bb7c12bcd73b291ce1bb4bba08610cdb6b88e` |

## Scoped rendered Mac follow-up

After `416e3e44`, the explicit DEBUG `--review-fixture` route was inspected before launch. It bypasses production generation opening, legacy import and Keychain; the store is in memory and credentials/server/playback/media/notifications are synthetic. Cloud/watch delivery is absent. A private fixture voice actor is now injected through the existing factory: English yields `one`, Japanese yields `一`, and neither microphones nor Speech APIs start. The old test launchers/cleanup using only retired `FASTLANE_SNAPSHOT` flags remain unsafe and were not run.

Initial comparison used native Mac build `build-3b8b63b60b534b299a218c96f243c4c1`, including a catalog launch that inspected wide Home. After it exposed focus loss, build `build-c05c5ac5186444c5ac5b5561217f5617` verified the fixes with `--manual-review-fixture --audio-fixture --light-fixture`. Accessibility state and the rendered app showed:

- Home Return opens the available synthetic review with the answer field focused.
- An incorrect answer remains visible and cannot accept further typed edits. The initial build lost focus after Delete; the correction now clears/unlocks the field and focuses it again.
- Voice opens directly in Listening. Stop produces an editable English transcript; Use keyboard restores the focused answer field. The initial build lost that focus and is superseded by this correction.
- A Japanese transcript containing `一` displays the kana-correction message and disables Check answer. Use keyboard restores focus. No recognized answer was sent to a real account.
- Typed meaning followed by romaji-to-kana reading retains next-question focus. The completed summary preserves the first wrong answer (`0/1`), shows “Missed · current level (1)” and returns Home with Return. Only simulated synchronization ran.

The desired-focus binding now accounts for Mac editability and inherited enabled state; temporary disabling must not erase the intent to focus. Voice/settings release focus before presenting and restore it on dismissal for typed phases. The same sheet/input fixes apply to Katakana, whose rendered behavior is still pending. Source review additionally required an immediate iOS disabled-event guard before its deferred focus update, with a second guard at execution; this final iOS-only addition is compiled but has not run on a device/simulator. Marked-text/kana conversion logic is unchanged.

The sample process was closed. No XCTest/Swift Testing suite, populated-store migration, real ASR, real account, device/signed service or benchmark ran. Browser access to the open WaniKani page was declined; no page content was read or alternative browser access attempted. The local original source remains the visual/interaction reference. This manual subset does not close the acceptance list above.

Final builds after the iOS event guard pass on Mac (local ad hoc signing) and generic iOS Simulator (signing disabled), with zero native-summary errors/warnings. All four follow-up Swift files pass formatting/strict SwiftLint. Inventory parses 266/266 files without gaps/context issues: production 21,239 physical lines (+15); tests 23,745 (+28 fixture lines, no assertion ports); tooling 282. Frozen V1 remains unchanged.

| Follow-up evidence | SHA-256 |
| --- | --- |
| `.build/Results/build-3b8b63b60b534b299a218c96f243c4c1.build.json` (initial Mac comparison) | `eb98dd31794fb53aa1f1f936b19d3d61d9f1564c299e0dba1cde4b5e62953e2d` |
| `.build/Results/build-c05c5ac5186444c5ac5b5561217f5617.build.json` (manual Mac build) | `c3fd785f3b203f53b579ae4addd04c09c736c9add5a55d0ee6fb4e6cd383562b` |
| `.build/Results/build-f99a1f55a9cb421d9a1799aaface241e.build.json` (final Mac) | `5fcddf68fd84eed51814ae360de4ee4f324137dca7342d54f34bb88c52f92e71` |
| `.build/Results/build-b80a16170b51412bba503bbdd816d376.build.json` (final iOS Simulator) | `07d61c7986e64ce63f4617f24a38c47848176884115823ec3683573e2a3322b2` |
| `.build/Reports/NativeFocusFinalInventory.json` | `5017afaaf120ea2c6cd40fc4266b464118061b1b0ab02e8a06df82e9f325d59d` |
| `.build/Reports/NativeFocusFinalComparison.json` | `55f40f226fb0155ae9ff1ed281e8daf386605f1c5e48b21bda05382d23328832` |

## iOS-first adaptive presentation

Following `e06c686f`, the owner made iPhone/iOS the primary design target, with iPad/Mac adapting from the same screens. This pass changes eight existing SwiftUI files, removes fourteen presentation-only OS conditional blocks and introduces no file, platform wrapper, capability registry or alternate feature flow. Storage, grading, synchronization and encoded values are unchanged.

- Catalog, reviews, lesson navigation, material editing and Voice use the shared title/back-button APIs. Catalog search lets SwiftUI choose placement while preserving its search binding and visible toolbar actions.
- Material editing and quick settings use native form presentation sizing instead of desktop minimum frames. The keyboard Done toolbar uses the shared keyboard placement. Katakana no longer imposes a desktop-only minimum size.
- Reviews default to stacked portrait content. Their allocated study viewport switches to side-by-side question/answer columns at width ≥560 and height <360 points, except at accessibility text sizes. These are content budgets, not device identifiers or Apple-prescribed breakpoints. Grouping the response prevents its feedback/input/buttons from turning into extra landscape columns. `AnyLayout` retains the input subtree; resizing no longer sends an extra focus action. The fixed input height cap is removed, and retry/correction controls stack at accessibility text sizes.
- Lesson order uses SwiftUI 27's native reorder container with explicit accessible up/down actions. Its private move method preserves the framework's ordered source selection, rejects stale/invalid destinations, and writes through the existing settings owner. This replaces mobile-only edit mode and desktop-only arrow controls without changing stored preferences.

Primary API evidence was checked against current Apple documentation and the installed Xcode 27 SDK: [semantic toolbar placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement), [shared title display](https://developer.apple.com/documentation/swiftui/view/toolbartitledisplaymode(_:)), [native search](https://developer.apple.com/documentation/swiftui/view/searchable(text:ispresented:placement:prompt:)), [search toolbar behavior](https://developer.apple.com/documentation/swiftui/searchpresentationtoolbarbehavior/avoidhidingcontent), [form sizing](https://developer.apple.com/documentation/swiftui/presentationsizing), [keyboard placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/keyboard), [reorder container](https://developer.apple.com/documentation/swiftui/view/reordercontainer(for:itemid:isenabled:move:)) and [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout). Native platform-specific effects are intentional: an inline title modifier may have no effect on Mac; keyboard placement maps to the platform's supported keyboard interface. No replacement platform framework is needed.

Remaining shared-UI OS conditions are tied to unavailable keyboard hints/Japanese input, iOS audio/activity/background behavior, notification options and opening system settings. Service and app-scene boundaries also remain where their APIs differ. Deleting those branches without a replacement would remove functionality; the [architecture](../Architecture.md#remaining-non-swiftui-boundaries) records the retained bridges.

Mainboard `ce366957`, Xcode 27/Swift 6.4: canonical Debug builds pass for generic iOS Simulator and native Mac (local ad hoc signing), with zero native-summary errors/warnings. All eight changed Swift files pass formatting/strict SwiftLint, with zero final rewrites. Mainboard inventory parses 266/266 files without gaps/context issues: production 145 files/21,226 physical lines (−13); tests 116/23,745 and tooling 5/282 are unchanged. V1 remains SHA-256 `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`. The separate AppIntents metadata note and historical warnings retain their prior scope.

The explicit `--review-fixture --manual-review-fixture --audio-fixture --light-fixture` sample installed and launched on the already booted iPhone 18 Pro/iOS 27 simulator, using only isolated synthetic services. Xcode exposes the preview through Device Hub; computer access to that app was denied, so no rendered iPhone interaction, screenshot or rotation was inspected. No workaround was attempted. The sample process was terminated and its absence checked; no simulator reset, uninstall, real account, real exercise, real speech or production-store opening occurred.

This is compiler/source evidence, not phone/iPad/Mac usability acceptance. Still inspect portrait/landscape soft and hardware keyboards, draft/marked text/focus through resizing, search reachability, form sizing, native drag/keyboard/VoiceOver reordering and preference persistence. Largest Dynamic Type in short viewports remains a specific acceptance gap: the review answer area has no scrolling fallback and the details question header retains its existing height budget. Do not claim comprehensive accessibility from the smaller layout improvements. Old reorder tests locating desktop arrow buttons must be ported to the shared native/accessible behavior without weakening order/persistence assertions. Formal XCTest/Swift Testing and broader migration/device gates remain deferred to the final stage.

| Adaptive evidence | SHA-256 |
| --- | --- |
| `.build/Results/build-d43a31f131d74b03937e5dc003205cbb.build.json` (iOS Simulator) | `d6357ffb33af5a2e8a180714080cef13be20bb04a085ac70233ff3f906ab7709` |
| `.build/Results/build-960265c40862431f9d44e743ecc4b363.build.json` (Mac) | `4ffcc01c33a88401b424831ee62074f894f97e8eac426a2f9b1e4466568b3590` |
| `.build/Reports/AdaptiveUIInventory.json` | `4333aa1b08450f83a0fb0de4393823d45009d49dd0091d8559caa6462bc8dd2b` |
| `.build/Reports/AdaptiveUIComparison.json` | `859fb7438027b6a592ecd4cac2c78b2a94e3806a8366cbbc54cfc00c391ad320` |

## Scrolling and lesson parity follow-up

After `061066f0`, source review addressed the review-overflow gap rather than treating it as accepted. One permanent `review.scroll` surface now contains progress, question, answer/actions and revealed details. Its content fills the available height when it fits and can grow vertically when it does not. The answer column keeps its natural height, revealed answers no longer stop at two lines, and the details header no longer has the 170-point cap. Progress and details actions reuse the existing large-text control layout. Scrolling never dismisses the keyboard; a simultaneous horizontal font gesture lets vertical drags on the question reach the scroll surface. No geometry-keyed identity, replacement input, forced focus or scroll reset is added.

`NativeSubjectDetailsView` now shares its existing content through one private method: standalone presentations keep `subject.scroll`, while the existing `reviewQuestion` presentation returns content into the review's scroll surface. Loading tasks, editing sheets and related navigation remain outside that branch. No extra configuration flag, view type, model or writer is introduced. The short/wide breakpoint is now height <420 points for the full review viewport, including progress, rather than the earlier <360 study-only budget. Width remains ≥560, with stacked content at accessibility text sizes. These are layout budgets requiring rendered acceptance. Apple documents the shared [keyboard-dismissal control](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)) and [size-based bounce behavior](https://developer.apple.com/documentation/swiftui/view/scrollbouncebehavior(_:axes:)); their behavior was also checked against the installed SDK.

Three additional differences were verified against the same pinned original source and corrected:

| Original behavior | Shared implementation correction |
| --- | --- |
| Lesson picker and subject chips use `japaneseText(subject,imageSize:)`, including image-only radicals | The picker and teaching strip receive the already-loaded `CatalogSubject` values rather than lossy summaries. Their existing radical image URLs render through `RadicalImageView` and the shared cache; no new store query, image resolver or model is added. Unused image/custom-font callbacks are removed. |
| Teaching `UIKeyCommand` entries have empty modifier flags and do not handle quiz input | The existing teaching key handler now also requires empty modifiers, preserving Command/Option/Control system editing/navigation commands. The quiz guard remains. |
| `LessonsViewController.allowsCustomFonts()` is false | Lesson quizzes use the system font and cannot cycle review fonts. Reviews/practice retain selected custom fonts and saved font sizing. |

Lesson tiles now use native adaptive minimum column widths, not a fixed four/two-column count. Tile heights are minimums, meaning labels can wrap at accessibility text sizes, and selection/start controls stack there. Ordinary phone widths retain the compact grid while iPad/Mac can use more columns. This is a native adaptation, not a new platform flow. The existing live lesson success-rate display remains an intentional shared native difference; it is not a missing grading feature.

Resource review found nineteen unused legacy control-image sets still in the iOS asset input. Seventy-four tracked files/32,688 source bytes are removed and enumerated in the [retirement manifest](2026-10-20-native-retirement.json), along with dynamic lookup/config/build-membership evidence and preserved responsibilities. The current kanji `.icon`, fallback AppIcon, Paper, SRS artwork, custom symbols, fonts/catalogs, watch resources, frozen fixtures and three protected off-target owner edits remain. `assetutil --info` on the final compiled iOS `Assets.car` shows UsagiUnagi icon/vector layers, Paper, SRS stage names and custom symbols, with none of the retired control names. This is not an installed-size, Release or visual-control acceptance claim.

Canonical Debug Mac/iOS builds pass on Xcode 27/Swift 6.4 through Mainboard `ce366957`, with zero native-summary errors/warnings. Six changed Swift files pass formatting/strict SwiftLint/UI rules without final rewrites. Inventory parses 266/266 files with no gaps/context issues: production 145 files/21,241 physical lines (+15 for overflow/lesson parity); tests 116/23,745 and tooling 5/282 remain unchanged. No frozen V1/schema/encoded-value change occurred. The V1 SHA-256 remains `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.

The final Mac build ran only with explicit `--review-fixture --manual-review-fixture --audio-fixture --light-fixture`. Native accessibility state and a rendered view confirmed Home Return opens the review with its answer field focused, question/input/submit remain visible in the normal-sized shared layout, and a wrong answer becomes locked with retry/reveal/Continue controls and updated accuracy. The computer connection stopped when attempting Reveal inspection. The same explicit synthetic app process was still running, then was terminated and its absence checked; no revealed-details result is claimed. No production account/store, real exercise, real ASR, permission prompt or old test launcher ran. Device Hub access remains denied; no retry or alternative route to its preview was attempted.

Remaining acceptance includes the newly unified revealed-details scroll, actual vertical drags over the question, keyboard/caret/drafts through resize, extreme Dynamic Type and short windows, image-only radical picker/strip rendering and lesson selection/modified keys/system-font quizzes on iPhone/iPad/Mac. Final test ports must target `review.scroll` for embedded details and retain `subject.scroll` for standalone details, update lesson-view constructors to the existing catalog values, and preserve all content/order/persistence/keyboard assertions. No XCTest/Swift Testing suite ran. Broader migration, account/sync, signed-service/device and final Release/dependency gates remain open.

| Follow-up evidence | SHA-256 |
| --- | --- |
| `.build/Results/build-adb0fc0cfb394147824803834c98dbf3.build.json` (iOS Simulator) | `e9678c2adcbde86556daa813a92a848da7055694b1586df27d32060cec281a3b` |
| `.build/Results/build-9f8343ee46b24d7ba10272b57ef56210.build.json` (Mac) | `79b54d0c0f24a4124597f7d9d5c1782dff89c2fd1aeb68c015f283f8b7b81c17` |
| `.build/Reports/AccessibleStudyInventory.json` | `66367a6846e0b86380f2dc7251f70e8424210b996ae3a744c87dce332fc4929a` |
| `.build/Reports/AccessibleStudyComparison.json` | `0778bad2942bb3c89be8664c05db9a5e4bba04d3849808fff2a0c07ba77ac56f` |
| `.build/Reports/AccessibleStudyAssets.json` | `8a87a2ac72aa8acfbf51cb14c447814935ad1ad5354298b25382faf8922bfea7` |

## Native navigation and final test ports

Commit `95b0207d` applies the iPhone-first follow-up in five existing UI/app files, with no new platform utility framework. `StudyTabs` now uses `.sidebarAdaptable`, preserving phone tabs while allowing the system's larger-window navigation. The Refresh command is shared with hardware-keyboard iPad instead of being compiled only for Mac. Lesson Back uses the semantic `.navigation` toolbar placement rather than an overlay above page content; its action and accessibility identifier remain unchanged. The unused `supportsAudio` flag is removed from both review settings owners: every caller already supported audio. The real iOS audio-session interruption option remains conditional.

The installed Xcode 27 interfaces confirm sidebar adaptation, `Scene.commands` and navigation toolbar placement are available on both deployment targets. No `UIDevice`/idiom or size-class platform fork remains in the inspected active shared UI/app scene files. Remaining branches cover unavailable keyboard/IME hints, audio/activity/notification/background services and scene lifecycle/window policy. The Mac minimum window size remains a scene policy awaiting small-window acceptance. Native sidebar presentation, toolbar placement and keyboard command delivery still need rendered iPhone/iPad/Mac checks; no new screenshot or GUI interaction is claimed.

Test-stage review found and fixed two production regressions. The generation opener tried to publish an already read-only capture; its fix and separate-process evidence are recorded in the [opening checkpoint](2026-10-20-native-store-opening.md). Expired connected accounts now produce typed, model-owned incidents, acknowledged once and deferred during study. A constrained reconnect verifies the saved stable account ID before downloading or committing credentials; a normal connection still permits deliberate account switching. Tests cover mismatches, stale prompts, late responses/cancellation, overlapping operations and preservation of sessions, notes and pending reviews. This uses the existing model, sync lane and shell, without another platform flow.

The original API corpus exposed two rejected compact date spellings. The reader now uses immutable native `Date.ISO8601FormatStyle` for dashed and compact dates. Apple's [format-style documentation](https://developer.apple.com/documentation/foundation/date/iso8601formatstyle) specifies optional fractional seconds with Swift 6.2 onward; the installed compiler is Swift 6.4. All sixteen original spellings, exact profile/subscription/progression values and nanori readings pass. The obsolete PromiseKit/Hippolyte API test helpers retire only after that port. The remaining protobuf package test covers all 22 historical part-of-speech codes/descriptions; SwiftProtobuf 1.39.0 and its revision/plugin are unchanged.

| Local evidence | Accepted scope |
| --- | --- |
| `SharedFinalMac4.log` | 544 shared functions/72 suites pass on Mac; later test-only path normalization is covered by `NativeOpeningMacFinal2.log` (four opening functions, including parameter cases) |
| `test-a99d330695b94f53b0171c09142bd0eb.xcresult` | iPhone simulator: 544 functions, 805 parameterized executions, zero failures/skips; source includes the never-opened damaged-store fixture, before the Mac alias normalization |
| `NativeHostedTests.log` and its result sidecars | iPhone simulator: 73 hosted functions/15 suites, 102 executions, zero failures/skips. Generated `.xctestrun` arguments for both hosts explicitly contain `--review-fixture` before execution |
| `NativeProtobufTests.log` | One Swift Testing function with 22 historical raw-code/description cases passes |
| `build-55da59163c6043619e2aa413ef88d03f.xcresult` | Native Mac Debug app builds with the final native navigation changes |
| `build-for-testing-05ea20be47fc42e08b60f411cf3ae9ff.xcresult` | iOS app and both hosted test targets compile; native input Coordinator visibility remains internal |
| `build-af6d23a9b2b043b7a4631051399fcd56.xcresult` | iOS/watch/widget Release builds; one existing empty WatchKit-host storyboard warning remains |
| `build-f43810af8baa4779b93ac4a2a5357580.xcresult` | Mac Release builds; native summary has zero errors/warnings |
| Mainboard `1d6b2d7` targeted gate | All 228 Apple/Swift regressions pass; see [tooling evidence](2026-10-20-mainboard-reports.md) |

Development failures were retained and corrected rather than skipped. Shared fakes initially referenced retired methods and had two throwing-macro errors. The cloud test incorrectly treated `Task.yield()` as an AsyncStream drain; bounded waits now observe the actual account/loading/quota transition before continuing, preserving exact writes/history checks. The first iOS run passed 543/544 functions: a newly damaged-store test released its setup container while checking bytes. It now damages a never-opened coherent copy while retaining its idle source, preserving every byte comparison. A focused Mac rerun then exposed the helper's `/var` versus `/private/var` relative-path key bug; canonical root/entry paths fix that comparison without excluding WAL/SHM. Hosted compilation also caught a throwing `#require` expression and two retired grading adapter references; explicit independent grading expectations preserve the original role/reading corpus. The successful results above follow those scoped fixes.

The nineteen old writer assertion mappings were audited before deleting their superseded suites. Native stale-note tests now include ACK followed by fresh authoritative replacement. Archive/preference and review integration assertions remain, and the empty UIKit test delegate is removed. All ReviewFlow launch/open/activation helpers require the DEBUG fixture marker; cleanup terminates without a production relaunch. Eleven missing UI fixture scenarios remain explicit failures before app creation, not skips or claimed passes. They and rendered original-app comparison remain open.

Whole production formatting/UI-rule checks pass for 158 files, and broad SwiftLint passes for 277 discovered files. The final inventory parses 257/257 classified first-party sources with zero parser gaps/context issues. Versus the preceding checkpoint, production remains 145 files and grows 21,241 → 21,379 physical lines (+138 for correctness); tests shrink 116 → 107 files and 23,745 → 22,461 lines; tooling changes 282 → 281. This is 1,147 fewer physical lines overall, not a production LOC reduction. Counts include the three protected, off-target owner files; source inventories do not prove target membership or behavior. V1 declarations and frozen store fixtures remain unchanged.

The final iOS/Mac Release main executables were inspected with the selected toolchain's `nm` and `otool`, each exiting 0. Their retained `Release{iOS,Mac}{Symbols,Linkage}.txt` files contain no `FMDatabase`, `FMResultSet`, `Hippolyte` or `PromiseKit` match. This is scoped main-executable symbol/linkage evidence, not a full nested-product or clean dependency-restoration attestation.

| Retained artifact | SHA-256 |
| --- | --- |
| `AdaptiveValidationInventory.json` | `8d4b3730b657201af758eae92e390c9a4d4902cc3836bcf2bf19c483778ee7e2` |
| `AdaptiveValidationComparison.json` | `4ea4d61378f45d7e33a612a09a9dba4cfb6d935dd9426ad99b5ad6eeb232a4c6` |
| iPhone shared `.tests.json` | `c88bc1512a7c74097e883fbc826bdf1aa1a9ffeb459f7a03d66d73d23a87c3dd` |
| `NativeHostedTests.log` | `4ac73245f70aab6a73c89fcb111f3d5b3033e093d72a21020d3976e300466648` |
| `ApplicationOpeningProbe.log` | `f6636f1f0d8b63acd9420e7571c0baab3f385f5a28b3fff5da9da0294de64e88` |

Fresh builds retain the six previously recorded shared-test warnings; incremental zero-warning summaries do not erase them. Fixture image CRC diagnostics, the empty watch-host lifecycle warning and AppIntents metadata-extraction notes remain scoped. No real account, exercises, cloud writes, microphone, signed service, GUI automation, PR, push or distribution was used in these gates. Remaining acceptance includes rendered keyboard/IME/draft and lesson/review flows, largest text/short windows, eleven UI fixtures, wider G7 failures/decoder compatibility, watch lifecycle and physical/signed services.

## Compact native scene and fixture follow-up — October 21

Following `25e68d3e`, the Mac-only 640×500 minimum frame and one-use window wrapper retire. The shared iPhone-first screens now receive compact Mac space directly; default Mac launch size/restoration remain native scene policies. The remaining presentation checks cover genuinely unavailable keyboard/IME, audio, prediction and notification APIs. No device-identity branch or generic platform utility is introduced. Apple's [sidebar-adaptable style](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable) documents the shared phone/tab/sidebar behavior already adopted.

The never-populated `blockingProgress` property and its global disabling modifier also retire. Native refresh already commits atomically while cached content stays usable. Its ported acceptance contract keeps Settings enabled and duplicate Refresh disabled, checks 864 learned kanji across foreground/settings changes, then 865 only after completion. The renamed test uses the existing one-shot URL driver with `App/Tests/HeldRefresh.json`; CI gives it a dedicated lane and both root shell tasks supply that configuration. This intentionally replaces the old reset-era global-blocking assertion rather than fabricating blocking behavior.

Supported missing fixtures now use explicit typed in-memory account responses, durable session events, exact Home distributions/empty/limit/vacation variants and the original four-subject/five-question review. No synthetic alert, real credential or timer triggers account expiry. Reduce Motion remains a prelaunch failure until a device has the real setting; the public environment value is read-only. These UI source ports compile but have no new rendered execution claim.

Three unused notification-task results now assert nil; companion delivery tests use a concrete MainActor probe instead of mutated captured variables. Three identical 68-byte PNG fixtures change only offsets 53–55 in the IDAT checksum: compressed pixels remain identical and all chunk CRCs validate. Frozen import/store fixtures and V1 remain unchanged.

| New local evidence | Scope/result |
| --- | --- |
| `SharedWarningFixiOS.log`, `test-640e7439a9124ee59fcf42621ebc8e87.xcresult` | Fresh iPhone shared suite: 544 functions/805 executions, zero failures/skips; six warnings and image CRC diagnostic absent. Precedes the two-line dead shell-flag removal |
| `AdaptiveFixtureBuild.log` | iPhone build-for-testing passes, explicitly compiles ported `ReviewFlowTests.swift` |
| `AdaptiveCompactiOSBuild.log`, root Results `build-for-testing-c6370a54f8a7451c8e976cbbb16f2a48.xcresult` | Final iPhone source builds for testing, native-summary zero errors/warnings |
| `AdaptiveCompactMacBuild.log`, root Results `build-ac9f86b610b0419abc20b1ad18f44c17.xcresult` | Final Mac build passes; two stale deleted generated-file cache warnings, with no current project references |
| `AdaptiveNativeHostedTestsFinal.log`, `test-a89b71fc38ba44b69efcb7fd9bb9e65f.xcresult` | Final 73 hosted functions/15 suites/102 executions pass, zero failures/skips. Both generated host argument arrays verified `--review-fixture` before execution |
| Scoped Mainboard lint | Nine changed Swift files pass formatter, SwiftLint and UI/parser rules; zero rewrites |

The first hosted invocation requested unsupported executor action `test-without-building` and exited 2 before native execution. The documented `test` action then produced the successful receipt above; the failed invocation is not a test result. TOML/YAML/JSON validation confirms both root tasks and CI select the exact renamed test/one-shot route. Build logs live in app Results; the two compact build bundles above are in `/Users/pedro/Developer/projects/.build/Results` because those invocations ran from the parent workspace. AppIntents metadata notes remain separate.

Mainboard `b9cc330` retains the earlier 228 Apple/Swift regression scope. Its broader suite recorded 1060 passed, one legacy-import isolation failure and eleven skips. After repairing editable-path leakage, both focused isolation witnesses pass; the full suite was not rerun. Managed-interpreter pyrefly preserves exit 1 with four unchanged dependency-editor TOML errors and 45 warnings. These broader failures are not suppressed or relabeled. The workflow now pins that unpublished local commit; no hosted Actions run is claimed.

The final inventory parses 257/257 files with zero gaps/context issues. Production falls 21,379 → 21,371 physical lines; tests grow 22,461 → 22,660 for the fixture ports; tooling stays 281. Categories include protected off-target owner files and do not establish compiled membership or logical LOC. V1 SHA-256 remains `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.

| Artifact | SHA-256 |
| --- | --- |
| `AdaptiveCompactInventory.json` | `9f05a7e964c62a88c4ab9eef8c90ee42236c92297e0632030006b348567c854e` |
| `AdaptiveCompactComparison.json` | `6f3a02372abe82b289afad09e73152f90bd555d1c9bafd025216ac247fb9d4c5` |
| Final hosted `.tests.json` | `0c12c5f6006d5287ba4111666400a30e591e8c32271b6d21046474a1d62cd39a` |

No GUI automation, Device Hub retry, browser workaround, live exercise, real recognition/cloud write, PR, push or distribution ran. Rendered compact/wide/keyboard/Dynamic Type acceptance, the held-refresh lifecycle publication question, wider G7 failures, watch single-target/private-default continuity and signed services remain open. The [watch audit](2026-10-20-widgetkit.md#watch-lifecycle-audit-october-21) records the concrete mirror-overwrite hazard; collapsing its old extension cannot be justified by compilation alone.

## Sync and curriculum correctness

October 21, following `1db42066`. A real store-backed regression demonstrated the held-refresh ownership bug independently of UI automation. Both refresh overloads committed the downloaded profile to SwiftData while a canceled waiting task prevented the model from publishing it. The RED run built successfully and failed only six publication assertions across the two cases. The existing synchronization/publication block now runs in one local MainActor task; the waiter checks its cancellation after that owner completes. Account/credential generation fencing, disconnect draining and caller-owned sign-in/reauthentication are unchanged. Both cases then pass within all 26 model functions, preserving the exact pending note/revision, credential and single download/no writes. No service abstraction or persistent property is added.

Curriculum coverage previously accepted unsupported SRS integers as reached and could count unstarted characters at threshold zero. It now filters unsupported stages before duplicate aggregation and limits thresholds to valid milestones. The read-only bundled library exposes its existing official-document hash; no resource/schema changes. An independent Swift/PDFKit extraction of the SHA-verified official PDF matches all 313/284/328 intermediate Kanken additions. Exact sorted-UTF8/newline digests, sample membership, elementary school equivalence, final Jōyō equivalence, fixed denominators across all four UI milestones and malformed stage/boundary cases now execute. Coverage remains separate from exam passing readiness and full-account calibration.

G7 adds three explicit synthetic restart images: partial capture, partial candidate and complete-but-unselected candidate. The actual opener preserves the complete seeded two-account state, source/retained bytes, abandoned artifacts, review revisions/attempt markers and note pending/attempt/issue fields; selects a fresh candidate UUID; and retains a subsequent note write/selection after reopen. All three cases pass on Mac and iPhone. No production generation code changed. These tests are same-process restart-image recovery, not an actual mid-copy kill, disk-full/file-protection/power-loss or frozen-store iOS adoption proof. Existing frozen-store separate-process evidence retains its prior scope.

| Final local gate | Evidence/result |
| --- | --- |
| Shared Mac | `StudyCorrectnessMac.log`: 551 functions/72 suites pass (92 persistence, 7 speech, 204 UI-model, 248 core). An expected read-only save fault is diagnostic output inside the passing rollback tests |
| Shared iPhone | `test-84b9edf28ac24eb98bd279b3c14067c2.xcresult`: 551 functions/827 executions, zero failures/skips, native-summary zero compiler errors/warnings |
| Hosted iPhone | `test-700b0b6dd8284752906deecb99d95e0d.xcresult`: 73 functions/15 suites/102 executions, zero failures/skips. Both generated host argument arrays contain `--review-fixture` |
| Debug Mac | `build-7f2d0ec9145c4f158dbeadf40a645a72.xcresult`: pass, zero native-summary errors/warnings; hosted iPhone action also rebuilds its app |
| Release iOS/Mac | `build-967b9df192694fcf80e5e7c7c6cd1ab0.xcresult` / `build-760a9e8110ac4a07a3c5baf7aec366a0.xcresult`: both pass. iOS retains one empty watch-host storyboard warning; Mac native summary has zero warnings |
| Mainboard | `1159d0d`: complete isolated suite passes 1067 cases, with 11 declared environment/fixture skips and three existing warnings. Requirement-parent typing is fixed with concrete TOML narrowing; checker retains exit 1 for zero errors/45 warnings |
| Swift quality/inventory | All five changed Swift files pass formatter/SwiftLint/UI-parser rules, no rewrites. Inventory parses 257/257 files with zero gaps/context issues; production 21,371 → 21,383 physical lines, tests 22,660 → 22,971, tooling unchanged at 281 |

Release inspection discovers all six packaged Mach-O files in the iOS Simulator/Mac app bundles, including the duplicated WatchKit stub, executable extension and WidgetKit extension. All twelve `nm -arch all -u` / `otool -arch all -L` calls exit 0; the forbidden FMDatabase/FMResultSet/Hippolyte/PromiseKit scan exits 1 with no matches. `StudyCorrectnessLinkage.json` retains each input/output hash and exact scope. This is stronger than the previous main-executable-only check, but does not attest source provenance, optimized-out static code, resource rendering or clean restoration. AppIntents metadata notes and older warning scopes remain separate.

| Retained artifact | SHA-256 |
| --- | --- |
| RED model regression log (`/private/tmp/usagi-model-waiter-red.log`) | `2f33aa231b3797e1d1459b2a811ec8fd2ebc19166c7d6f905b0bcbacb0ba436a` |
| Shared Mac log | `c16248f27865c9c15ee9786beb01d677ec66bc024a79f871559b4c67aedfc0b3` |
| Shared iPhone `.tests.json` | `5dec498ef6b71ede3befbf72efe1abd8b0850b1a1c6452b1bd7ec67bc101af20` |
| Hosted iPhone `.tests.json` | `1329e697fcde92769469d3c50a8fc83c1afa1c232bc63d86709498bebdb4f49e` |
| `StudyCorrectnessInventory.json` / `StudyCorrectnessComparison.json` | `dcc9dfe44a10a1a3a7cd988b5c0ec00a82d443bb82bd159826c2d90a3bb369f4` / `989d3b0f9bf59c6c1e53bc2dba140e48a593ca3bed03279548a386cd7d9dd041` |
| `StudyCorrectnessLinkage.json` | `f2a4672b3c9acf4cf81e541c3ab444c56e7d79a0bc679be9a38a93f90def2251` |

V1 stays SHA-256 `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`; bundled curricula stay `37b79abe5f90fdf068c8c946d8b776cf902c2e989c0480c3a27d6d1edfe39612`, and the reviewed source PDF stays `8c7513a4ecfc7d6ca2b8f8aa71313b9097e972bac7a43f8a568fe99a9a1d7285`. No new GUI/device access, live account/exercise, microphone, cloud write, global signing/trust change, PR, push or distribution occurred. The model-level held-refresh publication defect is resolved; rendered lifecycle/keyboard/layout acceptance remains open, as do wider G7 failures, full-account calibration, watch data/lifecycle conversion, signed services, clean restoration and unpublished CI prerequisites.
