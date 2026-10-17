# Modernization notebook

## Baseline

- Upstream: `davidsansome/tsurukame`, commit `d20defc`.
- Fork: https://github.com/Pedrexus/tsurukame
- Local branch: `codex/modernization-baseline`.
- Toolchain checked on 2026-10-17: Xcode 27.0 (`27A266a`).
- Simulator selected: iPhone 18 Pro, iOS 27.0.
- App deployment target: iOS 15.0; Swift language mode: 5.
- CocoaPods dependencies are checked in. Swift Package Manager dependencies are pinned in the workspace's `Package.resolved`.

Simulator validation does not establish physical-device microphone behavior or authenticated WaniKani sync correctness.

## Reproduce locally

Run from the repository root. `DEVELOPER_DIR` selects the installed Xcode for this command without changing the machine's global developer directory. Select an installed simulator with `xcrun simctl list devices available` if the destination differs.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -workspace ios/Tsurukame.xcworkspace \
  -scheme Tsurukame -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath ios/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Use the same command with `test` instead of `build` to run the scheme's enabled tests. The App Store screenshot suite is disabled in the existing scheme. Real-device installation requires configuring your own signing team and identifiers as described in `README.md`.

## Code map

| Area | Starting points | Why it matters |
| --- | --- | --- |
| Launch and navigation | `ios/AppDelegate.swift`, `ios/SceneDelegate.swift` | Services, login, scene lifecycle |
| Review interface | `ios/ReviewViewController.swift`, `ios/ReviewQuickSettings/` | Keyboard, submission, transitions, audio and settings |
| Grading | `ios/AnswerChecker.swift`, `ios/ReviewItem.swift` | Accepted readings, meanings, normalization, progress |
| Kana input | `ios/TKMKanaInput.m`, `ios/AnswerTextField.swift` | Existing typing behavior to preserve |
| Storage and sync | `ios/LocalCachingClient.swift`, `ios/WaniKaniAPI/` | Offline state, queued progress and API requests |
| UI conventions | `ios/Style.swift`, `ios/Tables/`, storyboards | Shared controls, layout and visual consistency |
| Existing SwiftUI bridge | `ios/Tables/ArtworkModelItem.swift` | Example of embedding SwiftUI in UIKit |

The initial inventory is 23,849 physical lines across tracked production Swift, Objective-C and header files, excluding Pods, generated code, protobuf output, tests, screenshot tools, formatting tools and Fastlane. This includes comments and blank lines and excludes storyboards, assets and other languages; it is a reproducible size baseline, not a complexity score.

```sh
git ls-files 'ios/*.swift' 'ios/*.m' 'ios/*.h' |
  rg -v '^ios/(Pods|Generated|SwiftFormatTools|AppStoreScreenshots|FontScreenshotter|FontScreenshotterUITests|Tests|fastlane)/|/Tests/|\.pb\.swift$' |
  xargs wc -l
```

The largest initial files include `ReviewViewController.swift` (1,747 lines), `LocalCachingClient.swift` (1,615), and `WaniKaniAPI/Sources/WaniKaniAPI/APIClient.swift` (986). Splitting files alone does not reduce complexity or total code.

## Sequence

1. Build and launch the upstream app; run existing tests. Record limitations before editing behavior.
2. Expand grading coverage before changing review input. Existing `AnswerCheckerTest` covers kana conversion and normalization, but does not directly exercise `checkAnswer` decisions. Cover primary/alternate readings, synonyms, typo tolerance, invalid characters and okurigana.
3. Prototype optional spoken answers through the same grading and submission path as typed answers. Keep review progress and sync semantics unchanged.
4. Modernize one screen at a time, using shared system controls, Dynamic Type, VoiceOver and adaptive layouts. Adopt SwiftUI where it removes meaningful complexity while retaining UIKit integration.
5. Simplify dependencies and asynchronous code in isolated changes backed by behavior tests. Compare production size, test results and user-visible behavior after each change.

## Voice-review experiment

- Start with explicit tap-to-speak, visible listening state, transcript preview, stop/cancel and typing fallback.
- Use the question language: English meanings and Japanese readings. Evaluate Apple Speech APIs against the supported OS/device/language matrix before choosing the implementation.
- Treat permission denial, interrupted audio, unavailable models and recognition failures as input failures, never incorrect answers.
- Do not grade provisional transcripts. Ignore callbacks from a previous question or cancelled recording.
- Preserve the existing distinction between accepted readings and alternative kanji readings. Recognition that produces kanji must not be converted into the expected answer merely because it matches the displayed subject.
- Test short isolated Japanese readings, homophones, long vowels and small kana on a physical iPhone. Speech transcription alone does not measure pronunciation quality.
- Add automatic advancement only after measuring recognition accuracy and latency. Keep correction and retry available before committing review progress.

## Validation results

- Build: **passed**, Debug for iOS 27.0 Simulator, signing disabled. Tracked app source and dependency lockfiles remained unchanged.
- Launch: **passed**, using the existing `-FASTLANE_SNAPSHOT YES` sample-data mode. The home screen rendered with the sample profile, review/lesson cards, chart and tab navigation.
- Screenshot: `ios/build/baseline/home-ios27.png` (local, ignored build artifact).
- Existing app unit tests: **24 passed, 0 failures** after the fix below. The initial attempt failed at package resolution because the build's formatter changed dependency manifests. Final successful result bundle: `ios/build/baseline/UnitTests-final.xcresult`. The separate WaniKaniAPI package test suite and live API prober were not run.
- Build warnings include protobuf `Sendable` compatibility, deprecated UIKit animation/key-window APIs and legacy ClockKit APIs. Swift 6 migration requires addressing these rather than simply changing the language mode.
- Build-system fix: added `--exclude build` to `ios/.swiftformat`. The build invokes SwiftFormat every time; with DerivedData inside `ios/build`, it previously formatted dependency checkouts and caused package-resolution failures on the next invocation. Restored only the generated checkouts to their pinned versions before retrying; verified they remained unchanged after the successful test build. No application behavior or dependency versions changed.
- Authenticated sync, real-device installation, microphone input and complete accessibility coverage have not yet been verified.
