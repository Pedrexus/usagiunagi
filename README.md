# 兔鰻 · usagiunagi

An independent, unofficial WaniKani client for studying Japanese, forked from [David Sansome's Tsurukame](https://github.com/davidsansome/tsurukame). The name is **兔鰻** in Japanese and Chinese localizations, and **usagiunagi** elsewhere: a rabbit–eel companion for your studies.

This fork is being modernized for **iOS/iPadOS 27+ and native macOS 27+**, using Swift, SwiftUI, system typography, SF Symbols and Liquid Glass. Shared statistics include Apple Swift Charts, level pace, focus items and curriculum coverage for estimated JLPT lists, Japanese school grades, Jōyō/Kyōiku and selected Kanji Kentei scopes. Coverage is not an exam pass prediction.

The iPhone/iPad app now uses a shared SwiftUI review layout while retaining the existing grading, lesson and offline progress workflows during migration. The new [native Mac app](native/README.md) currently supports statistics, subject browsing and inspection/recovery of locally saved work. iOS reviews now include optional voice input with transcript confirmation and typing fallback; real microphone validation remains open. Full SwiftUI migration and Mac review/lesson parity are still in progress. See the [open-task tracker](TASKS.md), [migration status](SWIFTUI_MIGRATION.md) and [statistics definitions](STATISTICS.md).

The [layered kanji icon](Branding/UsagiUnagi.icon) uses outlined SVG lettering and Apple's Icon Composer format. Brand localizations and store-name metadata are prepared in source; this fork has not been published to the App Store. Historical build target/module names and bundle identifiers remain for compatibility during migration. Choose your own signing identifiers for independent distribution.

WaniKani content is governed by [WaniKani's terms](https://www.wanikani.com/terms), separately from this repository's software license. Original Tsurukame copyright and license notices are retained. The [upstream App Store release](https://itunes.apple.com/us/app/tsurukame-for-wanikani/id1367114761) is Tsurukame, not a release of this fork.

## Building usagiunagi

Requires Xcode 27. Open `ios/Tsurukame.xcworkspace` for iPhone/iPad, or `native/TsurukameMac.xcodeproj` for Mac. These historical internal paths have not been renamed.

If you want to build the iOS app yourself, you will need to change the signing identifiers.

## Change the signing identifiers
You'll have to change the app bundle identifiers in the main target and app extension to match your Apple Developer Account.

1. You will need a registered Apple Developer Account. If you don't have one, you can get one for free at [Apple Developer](https://developer.apple.com/account/).
2. Next, you will need to open Xcode, and open `ios/Tsurukame.xcworkspace`, which is what you will use to build the app.
	1. You will need to click on the Tsurukame project in the left sidebar.
	2. For each target, in its Signing & Capabilities tab, turn on the automatically manage signing checkbox, as shown in the first arrow in the screenshot below:

    <img width="300" alt="Signing & Capabilities" src="https://user-images.githubusercontent.com/46784000/86614807-2a4f2780-bf79-11ea-8de5-dd3434b48afd.png">
3. If you already know your development team identifier, skip to step 4.
	1. Change the development team and bundle identifier as shown in the second and third arrows in the screenshot.
	2. You should see the development team identifier appear, as shown at the bottom of the screenshot. 
4. Open Terminal, and ensure the current directory is in the `tsurukame` directory, or use `cd` to change it if not. Then type the following command, replacing `7B2GP77Y4A` with your development team, such as `D526893WQ3`, and `com.davidsansome.wanikani` with your identifier, such as `com.mzsanford.wanikani`:
    `utils/set-team-product.sh 7B2GP77Y4A com.davidsansome.wanikani` 

# Update the CocoaPods dependencies
First, you will need to install [CocoaPods](https://cocoapods.org) if you don't already have it. The website suggests using `sudo gem install cocoapods`.

Next, you will need to switch the current directory to the `ios` directory using `cd`. 
Finally, simply install the dependencies using `pod install` or `pod update`.
