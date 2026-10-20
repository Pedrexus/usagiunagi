# 兔鰻 · usagiunagi

An independent, unofficial WaniKani client, forked from [David Sansome's Tsurukame](https://github.com/davidsansome/tsurukame). **兔鰻** in Japanese and Chinese localizations; **usagiunagi** elsewhere.

For **iOS/iPadOS 27+ and native macOS 27+**, using shared Swift, SwiftUI, SwiftData, Apple Speech and Swift Charts. The design keeps WaniKani's subject colors with system typography, SF Symbols and native Apple controls. Reviews support optional confirmed voice input. Statistics show pace, focus items and reference-list coverage; coverage is not an exam pass prediction.

Modernization is ongoing. iPhone, iPad and Mac now use the same SwiftUI root, account model and SwiftData store. Existing iOS accounts pass through a recoverable, one-way import before the native writer opens; original files remain available for recovery. Extra study reuses the review engine without changing scheduled progress. Legacy controller sources remain temporarily for isolated acceptance tests. Signed-device upgrades and platform delivery still need verification. See [current tasks](Docs/TASKS.md), the [migration plan and specification](Docs/Migration.md), and the [shared-code architecture](Docs/Architecture.md).

Open reviews, lessons or a subject using `usagiunagi:///reviews`, `usagiunagi:///lessons` or `usagiunagi:///subject/42`. Existing `tsurukame` links remain supported. Active native study stays in place until you choose to open an incoming request.

## Repository

| Folder | Purpose |
| --- | --- |
| `App` | One multiplatform app/project, system adapters and app integration tests |
| `Shared` | One Swift package: domain, persistence, speech, SwiftUI and unit tests |
| `Resources` | Layered kanji icon, names, hosted assets and Swift resource generators |
| `Docs` | Current workflow/tasks, statistics definitions and historical evidence |

## Build and test

Use Xcode 27 and open **`App/UsagiUnagi.xcworkspace`** for iPhone, iPad and native Mac. There is one `UsagiUnagi` app scheme and SwiftUI entry point. Restore the temporary locked iOS bridges with `pod install --deployment --project-directory=App`. Historical internal target/module and bundle names preserve compatibility. Set your own signing team and identifiers for devices.

[GitHub Actions](.github/workflows/apple.yml) uses Mainboard for bounded native builds/tests and result evidence. Mainboard is development infrastructure; it is not linked into the app. A standalone fork uses the public tool with its committed lock and does not need the parent workspace. See [development and CI](Docs/Development.md), including the unpublished tool-commit prerequisite.

The [Icon Composer asset](Resources/UsagiUnagi.icon) contains outlined SVG kanji layers. Localized store names are prepared in source; this fork has not been published to the App Store.

Original copyright and [Apache 2.0 license](LICENSE) notices are retained. WaniKani content is governed separately by [WaniKani's terms](https://www.wanikani.com/terms). The [upstream App Store app](https://itunes.apple.com/us/app/tsurukame-for-wanikani/id1367114761) is Tsurukame.
