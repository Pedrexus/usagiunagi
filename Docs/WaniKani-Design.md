# WaniKani dashboard reference

## Compact Tsurukame study follow-up

**October 22 detail access:** All information now uses an SF Symbol in the existing fixed
review tool strip, with the same explicit reveal action and Space shortcut. The former
button could lie below the visible content behind the fixed review controls. Reading
visibility and grading rules are unchanged; the 44-point action is available after
reveal without scrolling to the end of the details.

**October 22 text access:** the shared subject header scales with Dynamic Type and lets
long vocabulary wrap. Home cards can grow vertically; key account/section text uses
the primary style, and the lesson counter retains its natural width. Review progress
keeps its visual bar and one combined spoken count. The [accessibility receipt](Implementation/2026-10-21-adaptive-validation.md#native-accessibility-audit--october-22)
separates native audit findings, a standalone comparison and focused rendered checks;
it does not claim complete accessibility acceptance.

The owner's two further screenshots show a full-width purple review question with a narrow prompt/input boundary, and a short pink lesson header above dense meaning, reading, radical and mnemonic sections. The shared SwiftUI implementation removes the review card's outer padding/corners, compresses progress and prompt metadata, and places the check action beside the answer. Microphone, Ask later and the tools menu occupy a 44-point strip above the software keyboard through `safeAreaInset`; the same strip remains available with a hardware keyboard and on Mac. Quick settings, previous subject and font actions retain their existing handlers. Pronunciation remains available only after reveal, preserving the previous answer boundary. End session retains its wrap-up confirmation; native Back is restored for pause/resume, separately from explicit End.

Lessons use a shorter character header, compact labeled sections, horizontal related-subject tiles, and one bottom subject/position row. Meaning/readings/components precede the explanations; reading-first review details and hidden-reading visibility retain their existing rules. Dynamic Type can expand content, the page remains scrollable, and related subjects/tools keep 44-point minimum targets. The existing UIKit input boundary is retained solely for Japanese input-mode selection, marked text and caret handling; no additional platform check, native framework bridge, dependency or persistent model is added.

Anonymous reads of the official [level 1](https://www.wanikani.com/level/1), [level 2](https://www.wanikani.com/level/2) and [level 3](https://www.wanikani.com/level/3) pages on October 21 return 80, 147 and 130 unique subject links. Their per-type counts match the existing 357-row bundled preview. This checks population counts, not every field's freshness or grading completeness. The public [遜 page](https://www.wanikani.com/kanji/%E9%81%9C) also exposes teaching content, but anonymous HTML has not established the API's accepted/auxiliary-answer contract. The existing display catalog is sufficient for populated browsing without a token; it must not be turned into graded lessons or invented account progress. Preview rows now use unassigned status and the appropriate subject color. No new scraped corpus, exporter, Parquet or sample progress data is added.

Final Mainboard Debug builds, including the final button-label touch-target correction, pass on native iPhone 18 Pro/iOS 27 and Mac/macOS 27.0.1 with zero compiler/analyzer errors or warnings: `build-dcadfedc6ec1481e93a0426b8ffbeae1` and `build-395e4903d81f4fdbbba761d1a3eab5df`. Logs are `.build/Results/CompactStudyTargetsIOSBuild-20261021.log` and `CompactStudyTargetsMacBuild-20261021.log`. Strict lint passes on six changed Swift files with zero rewrites/failures (`CompactStudyTargetsLint-20261021.log`). Inventory parses 268/268 files without context issues (`.build/Reports/CompactStudyTargetsInventory-20261021.json`): production 151 files/23,078 physical lines, tests 112/27,575, tooling five/289. This presentation pass adds 41 production lines; it is not a LOC reduction. The V1 schema SHA remains `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.

Isolated native manual inspection confirms the compact dark review toolbar, no pronunciation before reveal, disabled empty-answer check becoming enabled on typing, and Quick settings opening/closing while preserving the unsubmitted draft. A dark lesson shows meaning, readings, components and both explanations without scrolling in the small fixture. The full 357-subject preview loads without an account; searching 一 returns nine real display matches with readings and type colors. Current captures and the two supplied references are retained under `.build/Results/CompactStudy-20261021/`: `lesson.png` and `review.png` are recaptured from the final touch-target build at 19:21/19:22 JST October 21; `real-catalog.png` retains its 19:17 pre-touch-target-correction scope, with identical catalog source. The fixture banner is development-only; study counts are synthetic, while the separate catalog capture uses genuine display fields. No answer is submitted, microphone started, private browser/token accessed or live signed service used.

After implementation/manual work, the [finish-stage pass](Implementation/2026-10-21-adaptive-validation.md#finish-stages-14--october-21) corrects group selection accessibility, combines review progress, caps wide subject reading width and restores native Back. Current iPhone UI regressions pass group select/clear, retained lesson/quiz selection and draft, Previous/focus, Quick settings/exact grading, pause/resume, incorrect/reveal/override, explicit End, combined Anki and landscape. The largest Dynamic Type review test enters through the existing local review link; it does not establish largest-text Home acceptance. That Home list's default XCTest swipe loses its accessible identifier, so its broader rendered/accessibility check stays open. Native root coverage also checks lessons/review completion, local reconnect, statistics and settings. Mac native pause/resume is manually checked; XCTest still times out before launch. Full IME, hardware keyboard, high contrast/VoiceOver, physical behavior and an authenticated full catalog remain acceptance gates in TASKS.

## October 21 owner-supplied account references

The owner's seven new iPhone pictures supersede the earlier compact-list preference where they differ. They show: the colored review question/prompt/input hierarchy; lesson composition and the subject strip; grouped lesson picking and interleaving; recently burned/community sections; level Guru progress and item spread; the forecast/recent mistakes/extra study; and prominent pink Lessons/blue Reviews actions. These are visual references, not a source of account counts or study data. Personal screenshots remain outside the tracked repository.

The implementation brings back solid lesson/review action surfaces, explicit start labels and SF Symbols; grouped native sections; separate Recent mistakes, Extra study, level progress and Item spread; recent unlocked/burned subject tiles and the community link. Existing account, vacation, lesson-limit, pending-upload and stale-progress rules still control availability. Recent tiles use confirmed saved assignment timestamps from the last 30 calendar days, omit future/hidden/inaccessible/pending items and open the existing subject screen. No persistent model or decoder shape changes.

The lesson picker supports whole/group selection, a normal preference-sized batch and optional type interleaving. Without interleaving, batches and explicit selections retain the account's supplied lesson preference order, including current-level priority; displayed grouping does not re-sort the queue. Interleaving alternates the three subject types while keeping each type's input order. A paused quiz retains its captured order. Components gain colored subject tiles, including image-only radicals. Review prompts now include the subject type. System type, semantic toolbars and native glass button styles remain shared across platforms. The shell respects the bottom safe area; app-wide notices occupy a separate row above navigation, keeping both toolbars and the floating tab bar clear.

| Shared subject surface | Color | Role |
| --- | --- | --- |
| Radical / reviews | `#0070B2` | Saturated blue, white foreground |
| Kanji / lessons | `#CE007B` | Saturated pink, white foreground |
| Vocabulary | `#9100E3` | Saturated purple, white foreground |

These are contrast-conscious adaptations of the supplied references, not sampled website hex values. Content cards stay opaque and system-adaptive. [Apple's current Liquid Glass adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), read October 21, places glass in the controls/navigation layer, recommends standard components and grouped forms, and cautions against excessive custom glass or toolbar backgrounds. Native toolbars, sheets, tabs and glass button styles supply those effects; the app does not reproduce Safari chrome or place glass behind every content panel.

Automated tests remain deferred under the owner's tests-last instruction. The final phase must cover recent-window boundaries, pending/stale omissions, level links, selection/batch/interleave order, paused quizzes, accessibility/contrast and keyboard flows. No real account exercise or microphone operation is required for the isolated visual comparison.

### Current implementation and manual evidence

Final Mainboard Debug builds pass on iPhone 18 Pro/iOS 27 and native Mac/macOS 27.0.1, both with zero native compiler/analyzer errors/warnings: `build-d3ce126441444e58b51f7054d87238d4` and `build-2c13046cdf014f3088d46c2ffa822392`. Logs are `.build/Results/WaniKaniStyleSelectionIOSBuild.log` and `WaniKaniStyleSelectionMacBuild.log`. The preceding native pair (`build-1c551dbab7ca4bbf9e064edd5ab9e3bc` / `build-4de9e74a5a134aedaa6c5520bb55cd73`) retains its navigation/layout scope before the final non-interleaved preference-order correction. Strict lint passes on thirteen changed Swift files with zero rewrites/failures (`WaniKaniStyleFinalLint.log`), followed by a fresh check of the final picker correction (`WaniKaniStyleSelectionLint.log`). Inventory parses all 268 files without context issues: production 151 files/23,037 physical lines, tests 112/27,575 and tooling five/289. The additional UI/projections add 152 production lines, not a LOC reduction; there is no new dependency or persistence schema.

Native iPhone captures are retained in `.build/Results/WaniKaniDesign-20261021/`. Home, lesson picker and the unsubmitted vocabulary review with keyboard were recaptured from the final source build at 19:00 JST on October 21; level progress, Item spread and lesson content retain the 18:46–18:50 navigation-build scope. The seven supplied website photos remain reference material; native sample counts and subjects differ. No private browser account, real exercises, microphone, permission prompt or live signed service ran. The earlier 18:13–18:20 captures predate this design pass and must not be labeled current.

Manual native accessibility inspection confirms Home's four lessons/twelve due reviews, current-level Guru values and stage distribution; the exposed Scroll Down action reaches lower sections. Group selection selects two radicals; individual taps clear them. With no manual selection and interleaving enabled, Start a batch opens five teaching pages in the expected order: 人, 一, 一つ, 口, 二. The second page renders the existing mnemonic/reading content and subject strip. No quiz answer is submitted. Full Select all/Clear, paused-session, Dynamic Type, dark/high-contrast, iPad/Mac rendering and broader original-flow acceptance remain open. The tooling's cached group custom action did not verify Clear, and pointer/drag scrolling returned `noWindowsAvailable`; the native semantic scroll action succeeded. These are not automated test passes or diagnosed application failures.

The manual pass also catches a genuine Home refresh loop: the changing raw TimelineView date repeatedly changes the load-task identity while rendering. A bounded native process sample shows repeated `NativeHomeDashboardView.load()` / `homeData()` work. The view now retains one schedule origin and keys time-based loading by minute, while retaining account/revision/preference/activity triggers. The sample process becomes responsive; scoped idle observations show 0.0% CPU after 38 seconds and again after roughly three minutes. `/private/tmp/usagi-wk-home-render-sample.txt` and `.build/Results/WaniKaniStyleHomeHang.log` retain the failed observation. This is a scoped manual correction, not real-device performance acceptance or an explanation of the owner's older navigation crash. Add a repeated-body/clock/account-change regression in the final test phase.

Calculated white-on-solid contrast for the three source surface colors is 5.30:1, 5.37:1 and 6.34:1 respectively. This does not establish all appearance/accessibility settings. Current study schema, frozen sources/fixtures and the three protected owner edits remain unchanged. Earlier Release, automated, signed and device receipts retain their source scopes.

## Earlier observations and implementation history

Observed 2026-10-18 and rechecked 2026-10-19 in the user's existing signed-in Chrome tab at [WaniKani](https://www.wanikani.com/). Read-only dashboard inspection; no exercise sessions, answers, edits or account changes.

The first row prioritizes pink Lessons, blue Reviews and a next-24-hour forecast. The next row places Recent Mistakes beside Extra Study. Level Progress follows with separate radical/kanji/vocabulary Guru counts, then Item Spread grouped by five SRS stages. Supporting unlocked/critical/burned items come later. White cards, light neutral page background, consistent spacing, short headings, visible counts and direct actions make the hierarchy easy to scan.

Use that hierarchy with Apple system typography and SF Symbols. Shared Home keeps lesson/review actions together; Extra Study is separate from the scheduled forecast. Subject colors remain consistent through level charts and catalogs. Keep native controls and accessible labels; retain lesson-limit explanations for VoiceOver. No mascot assets, proprietary artwork or custom website font files were copied. Sample mock figures must stay clearly labeled, and coverage charts must not imply calibrated exam pass probabilities.

iPhone, iPad and native Mac consume the same Home projection and navigation. Studies open above the tabs, with durable pause/resume through Home. The former legacy DEBUG host is retired; current native fixtures inject memory-only services into the shared root.

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

Short/wide reviews keep the meaning/reading strip below the colored subject, matching the
inspected historical screenshot. The October 22 viewport follow-up retains that arrangement
except below 140 points of available height, where glyph and prompt share a row so neither
disappears behind a landscape keyboard at very large text sizes. The shared input retains
its binding and native focus behavior; the renewed regression checks draft preservation
and question/prompt/input geometry through rotation. Question and response remain the same
two `AnyLayout` children across orientations; feedback actions scroll independently of
the question in either layout. The account/vacation header now scrolls
with Home instead of consuming study space. See the [exact evidence](Implementation/2026-10-21-adaptive-validation.md#home-and-review-viewport-follow-up--october-22).

In that short wide column, a standard small-control request also selects a smaller semantic
answer text style. Both native adapters still honor Dynamic Type; ordinary layouts retain
title2. This follows the measured 59-point viewport rather than capping accessibility sizes.

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
