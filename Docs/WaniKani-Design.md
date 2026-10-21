# WaniKani dashboard reference

Observed 2026-10-18 and rechecked 2026-10-19 in the user's existing signed-in Chrome tab at [WaniKani](https://www.wanikani.com/). Read-only dashboard inspection; no exercise sessions, answers, edits or account changes.

The first row prioritizes pink Lessons, blue Reviews and a next-24-hour forecast. The next row places Recent Mistakes beside Extra Study. Level Progress follows with separate radical/kanji/vocabulary Guru counts, then Item Spread grouped by five SRS stages. Supporting unlocked/critical/burned items come later. White cards, light neutral page background, consistent spacing, short headings, visible counts and direct actions make the hierarchy easy to scan.

Use that hierarchy with Apple system typography and SF Symbols. Shared Home keeps lesson/review actions together; Extra Study is separate from the scheduled forecast. Subject colors remain consistent through level charts and catalogs. Keep native controls and accessible labels; retain lesson-limit explanations for VoiceOver. No mascot assets, proprietary artwork or custom website font files were copied. Sample mock figures must stay clearly labeled, and coverage charts must not imply calibrated exam pass probabilities.

iPhone, iPad and native Mac consume the same Home projection and navigation. Studies open above the tabs, with durable pause/resume through Home. The temporary legacy host is selected only by the old isolated DEBUG screenshot test environment.

The open Chrome dashboard was rechecked during the lesson-settings integration on October 19. The primary action cards, forecast and level/SRS hierarchy still match this reference. Only the dashboard was read; no exercise was opened and no account setting was changed. Native lesson settings retain system typography and controls rather than adding a separate visual theme.

Home now uses the same compact native inset list on Mac, iPad and iPhone. This brings the Mac sections closer to the original iPad table hierarchy and keeps Lessons/Reviews first, followed by the forecast, extra study and progress. System row spacing replaces the former Mac grouped-form gaps; WaniKani subject colors, charts, Apple typography and glass controls remain. No new palette, typography or navigation theme is introduced.

## October 21 usability refinement

The user's current priority is a cleaner, more natural study experience. The WaniKani observations above are sufficient reference; no new private browser access was attempted. Two historical upstream App Store screenshots were extracted from the pinned `upstream/master` commit `d20defc38db78a844d49130031e54969d1907331` and their actual pixels inspected: [compact Home rows](https://github.com/davidsansome/tsurukame/blob/d20defc38db78a844d49130031e54969d1907331/ios/fastlane/screenshots/en-AU/iPhone%2011%20Pro%20Max-01_home_screen.png) and [subject/prompt/answer hierarchy](https://github.com/davidsansome/tsurukame/blob/d20defc38db78a844d49130031e54969d1907331/ios/fastlane/screenshots/en-AU/iPhone%2011%20Pro%20Max-02_lesson.png). These screenshots predate the pinned source's Orizuru hero; they are historical visual references, not a fresh render of that source. Its `HomeHeroItem.swift` was also inspected. The implementation deliberately favors the compact native flow requested by the user instead of reproducing its waves, large cards and custom styling.

- Home uses direct Lessons/Reviews list rows with visible counts, blue/pink subject identities, SF Symbols and full-row targets of at least 44 points. The separate Choose lessons route and original availability guards/shortcuts remain. Unavailable-study explanations move to the section footer. The saved-session route stays near the top. Native disclosure contains the detailed level-up scenarios and their limitations; the next review remains visible in the forecast.
- Reviews keep one answer input and focus owner. The question retains its colored subject and reading/meaning strip, with Previous moved to the progress area. The answer precedes its feedback, followed by one full-width primary action and separate retry/reveal controls. Revealed details scroll above a native bottom inset containing Continue or Anki grading, so those actions no longer follow the entire mnemonic in the scroll content. Correction menus, assessment confirmation, keyboard shortcuts, audio and voice routes remain. A 760-point reading width limits the reading column in a wide window; the existing short/wide layout and accessibility stacking still apply.
- Stats starts with its existing Progress/Coverage/Focus selector instead of a second large title and repeated account identity. Sample, vacation and pending-upload notices remain. Cards use system headline/subheadline typography, smaller neutral containers and a 960-point maximum, matching Home's content width. Charts, source disclosures, coverage qualifications and all calculations are unchanged.

Only three shared view files change; no platform branch, preference, persistence model, grading rule, dependency or new UI abstraction is added. This presentation work adds 16 physical Swift lines overall, primarily to keep the revealed-answer actions outside scrolling content. Reducing those lines is not a reason to duplicate input or hide correction controls.

### Local verification

Mainboard ran both Debug builds through the selected Xcode 27 toolchain. iPhone Simulator and native Mac both pass with zero native-summary compiler/analyzer warnings or errors. All 556 shared test functions pass in 72 suites (four test batches: 92, 8, 206, 250). The isolated hosted iPhone `AppTests` passes 95 functions / 172 executions with the existing one restart-protocol skip and zero failures. The separate restart protocol was not rerun for view-only edits. Scoped formatting, strict SwiftLint and SwiftUI/parser rules pass on all three changed files, with zero final rewrites. No tests/assertions or the three preexisting owner edits are changed.

The Mainboard inventory parses all 259 scoped files without declaration-context issues. Production remains 145 files / 21,601 physical lines; tests 109 / 26,002 and tooling 5 / 281 are unchanged. `.build/Reports/UsabilityInventory.json` has SHA-256 `30f6985b2e476edc2324ae368d4dbc07f6a268143246d2dba62701cfed0e93fd`. The initial inventory invocation selected the older global command-line tools and refused before parsing; the successful run explicitly selects `/Applications/Xcode.app/Contents/Developer`, without changing the Mac's global setting.

| Evidence under `.build/Results/` | SHA-256 |
| --- | --- |
| `build-dffa49f5a7884e0ca5ecd24a71727fd1.build.json` (iPhone) | `47075e065384d115cff00c08780e53e3f744e311ab9f23bbd57f3bb6127a3822` |
| `build-47ca8e78858b4dd893609de7d0d7e7ad.build.json` (Mac) | `8db0b5f0f360c154fd63ef8b45b479cd45ae5221880a921b1c91518b13722d33` |
| `UsabilitySharedTests.log` | `14506d19005774f0f1a28d5bdd1190dbb51a51a0cd8cd029d2c4e80d47bf42c9` |
| `test-eab1e21df8634d279a31653a21d69c8a.tests.json` | `fe62214db711a165d8f5e21e2bf76abfe75b1efcff0753aa5e2c6d31ac196f4e` |
| `UsabilityLint.log` | `a980dafcb72209be5775de86db7d114911651eb490bb750603e0682b7b0d309b` |

This is source/compiler/unit evidence. The existing denial of device/computer access remains in force; only the isolated unit-test host started, with no normal account launch, UI capture or GUI automation. Rendered acceptance is still required for iPhone portrait/landscape and large text, safe-area action reachability, onscreen/hardware keyboard and marked-text focus, Previous/Retry/reveal/correction/Anki flows, disclosure reachability and VoiceOver order. Follow with iPad split windows and Mac resizing. The existing fixture-only UI approval request remains unanswered. No real exercise or private account was opened, and no signed-device, speech-capture or calibrated-statistics gate is closed by these results.

### Lesson progression and compact review headers

Source comparison with the same pinned original `LessonsViewController` and `LessonsPageControl` confirms its direct subject/Quiz strip, swipes and keyboard progression. The shared lesson flow preserved those routes but offered no explicit touch Next action. It now adds **Next**, changing to **Start quiz** on the final teaching page, in the native primary toolbar. The action reuses the existing page index and quiz route, clamping repeated events at the quiz boundary; it disappears for an empty lesson list and during the quiz. The study title stays inline, and the existing bottom Quiz shortcut uses a secondary bordered style. Chips, swipes, audio keys, Return/arrow keys, selection, Back and durable quiz ownership remain unchanged. This is an intentional discoverability improvement, not a claim that the original had the new button.

Short/wide reviews previously applied horizontal layout twice: question beside answer, then glyph beside its prompt inside the question column. The question now always keeps its meaning/reading strip below its colored subject, matching the inspected historical screenshot. Only the existing outer layout chooses columns. This removes the nested layout and gives the subject the full question-column width without changing the input subtree, focus owner, font preferences, feedback, grading or scrolling fallback.

Two shared view files change, adding seven physical Swift lines overall. No OS check, platform utility, dependency, model or new view type is added. Mainboard's iPhone Simulator and native Mac Debug builds pass with zero native-summary compiler/analyzer warnings/errors. All **556 shared functions / 72 suites** pass (92, 8, 206 and 250 in four batches), and scoped parser/UI rules, strict formatting and SwiftLint pass with no rewrite. No tests/assertions are added or changed for these presentation edits. Earlier hosted iPhone/Mac and storage receipts retain their own source scopes; they were not rerun here.

Inventory parses **261/261** files without context issues: production **145 / 21,608** physical lines; test **111 / 26,085** and tooling **five / 281** are unchanged. Receipts under `.build/Results/` and `.build/Reports/`:

| Evidence | SHA-256 |
| --- | --- |
| `build-191cc7fe5f034352aa83388798aae61f.build.json` | `0e9a0650c2fb30e6765428c7931d0fb54eafb084b6fcdb7a98b4b92d086cae26` |
| `build-c2fa528b6ee24b589eb96889c797b628.build.json` | `58c3978e5ae7defe78605655971f6f332644f580dbe750904967c2d3dab71260` |
| `StudyNavigationFinalSharedTests.log` | `02d5051645638d8414f7dc19a6dfa023819d7ff239fae4c33cf739b050b927bf` |
| `StudyNavigationFinalLint.log` | `43ffb4eacddbf5a536f92075a09543524d3791e220410189eedc931ae8e9b30e` |
| `StudyNavigationFinalInventory.json` | `8aa425592e3f870d2bc1b5b87383c0ae394971ae4f9f1cda7004cde2dad903e8` |

The final source hashes are LessonFlowView `0612cfe4f25e380d1d10e12bee12ddfd9c5ea6bd269d7302ff9e1dc35d76389d` and ReviewScreen `f4feb91bc9e7e676b443bcd2d393a582de4f090269ee043b4bc55a393d2f90f3`. The first passing compiler/shared receipts precede the final rapid-tap boundary clamp and remain historical; all final checks above ran after it. Actual UI execution remains restricted. Required on-screen checks now also include Next/Start quiz with single/multiple/empty/resumed lessons and repeated taps, one transition into the existing quiz, chip/swipe/keyboard/Back equivalence, toolbar behavior around related subjects, and the question/prompt/input at short heights and large text. No device restriction was bypassed, normal account opened or exercise performed; storage, voice, statistics, watch and signed-device gates remain open.

## Adaptive native toolbar priorities

The owner supplied Apple's current [SwiftUI toolbar collection](https://developer.apple.com/documentation/swiftui/toolbars/). A live October 21 read of that collection, its API pages and the [toolbar HIG](https://developer.apple.com/design/human-interface-guidelines/toolbars) supports native priority/overflow, restrained chrome and meaningful groupings. This records the retrieval date, not an inferred publication date. Content keeps its WaniKani colors; no toolbar background, tint, font, device flag or wrapper framework is added.

[`ToolbarItemVisibilityPriority`](https://developer.apple.com/documentation/swiftui/toolbaritemvisibilitypriority) is available from iOS/iPadOS 27 and macOS 26.1. Both installed SDKs and current app builds support it. Lesson Next/Start quiz and review Voice receive `.high`; the review font/history menu and Quick settings receive `.low`. Higher priority means an item stays visible longer as space contracts, not a guarantee of visibility at every width. Quick settings retains its original `.primaryAction` placement and identifier: existing UI flows tap it directly, so it is not deliberately relegated to a menu. The shared More menu remains for secondary font/history commands. Lesson progression is a native text button, retaining its clamp, action and identifier rather than relying on an ambiguous forward glyph.

Home's Search/Settings and saved-work/refresh toolbar content is now explicitly limited to `path.isEmpty`. Pushed review, lesson and catalog routes provide their own contextual controls; the root does not add global Home controls to them. Action callbacks, keyboard handling, state, grading, pending work and the existing fixed Continue/grading content inset are unchanged. Only three existing shared views change, adding four physical production lines without another helper or platform check.

The new [`toolbarOverflowMenu(content:)`](https://developer.apple.com/documentation/swiftui/view/toolbaroverflowmenu(content:)) and `ToolbarOverflowMenu` type are available on iOS/iPadOS 27 and visionOS, but **unavailable on macOS**. This is explicit in Apple's page and the installed macOS SwiftUI interface. Adopting them directly would require a platform-specific path; the shared toolbar keeps semantic items/priorities instead. [`ToolbarSpacer`](https://developer.apple.com/documentation/swiftui/toolbarspacer) is cross-platform, but these groups need no additional forced gap. Customization/minimization are not added without a demonstrated need.

Both final Mainboard Debug builds exit 0: iPhone 18 Pro/iOS 27 and native Mac/macOS 27.0.1, with zero compiler/analyzer warnings/errors in their summaries. Strict swift-format, SwiftLint and parser/UI rules pass on all three changed files with zero rewrites. Inventory parses 261/261 files, no context issues: production 145 / 21,679 physical lines (+4), tests 111 / 26,626 and tooling five / 281 unchanged. Earlier `BeforeSettingsPlacement` compiler logs are retained before restoring Quick settings' direct placement; only the final receipts below cover the committed layout policy.

| Final evidence | SHA-256 |
| --- | --- |
| `build-8ce12210e2f347c9beff921747d33cd0.build.json` (iPhone) | `eed147bb2c5e8d4383f7ba2a58e5164dc407843f114a0414faa4d4da52d6bb6e` |
| `build-39c19767b7a447d4aafce7388643fbb1.build.json` (Mac) | `f665fc987a7e192fb7721764ea772e0a7e1e5eae9de1915225bfec2804044682` |
| `.build/Results/Toolbar27Lint.log` | `a980dafcb72209be5775de86db7d114911651eb490bb750603e0682b7b0d309b` |
| `.build/Reports/Toolbar27Inventory.json` | `647cf64938c30fc46737f11ba6ec4424092efbddcf61c467d81b17c0455b0558` |

This is source/compiler evidence. No tests/assertions are added or removed for a presentation-only change, and no new shared/app/Release or rendered pass is claimed; the API/storage receipts at `3153d1bc` retain their source scopes. Actual narrow/landscape/Dynamic Type overflow, one-tap settings at ordinary widths, menu keyboard/VoiceOver access, Next/Start quiz and root-toolbar restoration after Back remain required on-screen checks under the existing restriction. Storage, voice capture, statistics, signed/watch and hosted CI obligations remain in [TASKS](TASKS.md).
