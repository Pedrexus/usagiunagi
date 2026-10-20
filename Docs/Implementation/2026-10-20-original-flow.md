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
