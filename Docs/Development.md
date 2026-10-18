# Development and GitHub Actions

Use Xcode 27.0 / Swift 6.4; Mainboard selects the toolchain. The obsolete Swift 5.1 swiftenv pin and unused Clang-format config were retired. Use the stable iOS 27.0 runtime. Open `App/UsagiUnagi.xcworkspace`, select the `UsagiUnagi` scheme and choose an iPhone, iPad or **My Mac** destination. My Mac is a native macOS build; Catalyst and the iPad compatibility destination are disabled. `Tsurukame` remains the internal app target/module for existing callers and data compatibility. `Tsurukame` also retains the hosted unit-test scheme.

## Mainboard owns execution

Generic Apple patterns live in Mainboard: native arguments, committed package resolution, process-tree timeout, fresh result bundles, diagnostics, test verdicts and simulator URL delivery. There is no app `Tools` folder or custom CI shell driver. Schemes, test filters, fixtures and resource generation remain app-specific.

From Developer/Projects, use `mainboard run --as-is <task>`:

| Task | Check |
| --- | --- |
| `usagi-restore`, `usagi-resolve` | CocoaPods deployment lock and committed Swift packages |
| `usagi-test`, `usagi-test-persistence` | Shared Swift Testing and separate-process production-store restart/catalog checks |
| `usagi-test-ios`, `usagi-test-app` | Shared iOS and hosted integration suites |
| `usagi-test-ui`, `usagi-test-ui-ipad` | Full iPhone/iPad acceptance except host-driven warm links |
| `usagi-test-warm-links`, `usagi-test-warm-links-ipad` | Actual custom URL delivery into an already running synthetic app |
| `usagi-build-mac-tests`, `usagi-test-mac` | Compile native Mac UI tests, or execute them |
| `usagi-font-previews` | Check all eight shared-catalog font previews and PNG attachments |

Focused `usagi-test-*` tasks use the same executor. Each Xcode execution creates a unique `.xcresult` under `.build/Results`, streams native output and preserves native failure/timeout status. Successful test execution also requires actual passing cases. Inspect an exact bundle with `mainboard apple results <path> --json` or `mainboard apple diagnostics <path> --json`. A build-only pass does not establish UI acceptance. Simulator runs sharing a device must run sequentially. Native Mac UI fixtures also ignore saved window restoration through a process-only launch argument; they never clear the real app's saved windows or account data. Run interactive Mac and simulator UI acceptance sequentially. Capture only the app window in Mac screenshots.

A standalone checkout can run the same commands directly with Mainboard installed:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mainboard proc timeout 180 pod install --deployment --project-directory=App
mainboard apple execute App/UsagiUnagi.xcworkspace --scheme UsagiUnagi --action test \
  --destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  --derived-data .build/Xcode/iOS --only-testing AppStoreScreenshots/ReviewFlowTests \
  --skip-testing AppStoreScreenshots/ReviewFlowTests/testNativeTabsPreserveWarmStudyLinksAndReturnToStatistics \
  --setting CODE_SIGNING_ALLOWED=NO --timeout 1800
```

The warm-link test adds `--url-test App/Tests/WarmLinks.json` and selects only its dedicated test identifier. The test writes fresh UUID markers inside its synthetic runner's data container; Mainboard allows only configured local routes and requires every route plus the test verdict to pass. It does not inspect browser credentials or use a real WaniKani account.

## GitHub Actions

The workflow runs shared tests/restart checks, iPhone/iPad acceptance and native Mac acceptance on the official [`xcode-27` image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), selecting `/Applications/Xcode_27.app`. It uses read-only repository permissions, pinned action/tool commits, cancellation of stale branch jobs and seven-day result artifacts. Synthetic accounts require no token, signing certificate or publication secret. No release or store deployment is configured.

Mainboard is pinned to `phvv-me/mainboard@7acaf736c8bae16f8b028678384fe83bb728c51b`, with `uv sync --locked` restoring its own environment. **That commit currently exists only locally on `codex/apple-development`. It must be published before the app workflow can fetch it. No push is authorized or performed here.** The prepared Actions workflow has passed local syntax validation; no hosted CI pass is claimed.

## Source and resources

`Shared/Package.swift` remains the authoritative shared dependency manifest. App package locks and `App/Podfile.lock` remain committed. FMDB, Reachability, SwiftGen and Hippolyte still serve active iOS migration callers; Mac's runtime has no CocoaPods dependency. Both app CI jobs restore the unified project's generated integration/file lists before building. `pod install` preserves a post-integration guard so iOS framework hooks do not run for the native Mac destination.

App-specific generators are in `Resources/Generators`; the legacy protobuf schema is beside `App/WaniKaniAPI/Schema`; the production persistence executable is in `App/Tests/PersistenceProbe`. The Swift Testing suites live with Shared, hosted integration suites with App, and XCUITest remains appropriate for actual UI interactions.

CircleCI, upstream Fastlane publishing/signing, unused snapshot capture, Xcode Cloud release notes, obsolete store screenshots and upstream Firebase deployment were retired. Generated Pods/build caches are ignored. Fonts and historical link-association references are retained under Resources/Hosted. Previous result logs/screenshots remain under ignored `.build/Previous`; durable receipts remain in Docs/Validation. No command deploys to the original author's account.

The [levels 1–3 display preview](../Resources/Fixtures/README.md) contains 357 real catalog references read from WaniKani's visible level pages without an API token. Mainboard exported `Resources/Fixtures/free-levels.parquet` with Zstandard; the app reads matching JSON through Foundation. Mac Account → Preview free levels 1–3 opens it offline, with negative local IDs, no assignments/account identity and no uploads. These are display readings/meanings, not full accepted-answer rules, mnemonics or real WaniKani IDs. Complete review/lesson fixtures still require an authorized API catalog. Chrome was returned to the dashboard and no exercises or account changes were made.

## Font acceptance

Shared font tests use isolated preferences/directories and local URLProtocol responses to check activation, glyph filtering, stale completion/cancellation, failure/retry and cache preservation. Hosted iOS tests additionally activate the eight original font files and verify the existing archived selection format. Native UI fixtures use the installed Japanese PostScript name `HiraMinProN-W3`; a nonexistent family name silently falls back to Helvetica on Mac and is not a valid Japanese test font. Fixture networking is local, delayed and cancellable; no live WaniKani exercises are used.

The shared library keeps network work outside UI state and publishes completion on MainActor. The debug URLProtocol fixture uses a mutex for its cancellation flag across the Foundation callback queue; it does not weaken production actor isolation. See the [official Swift sending-closure diagnostic](https://docs.swift.org/latest/documentation/diagnostics/sending-closure-risks-data-race/) and the [font checkpoint receipt](Validation/2026-10-19-shared-fonts.json).

## Audio acceptance

Shared tests cover voice/cache selection, subscription priority, cancellation/account changes, retained preferences and explicit deletion. The real AVFoundation backend is tested with a corrupt local file followed by a valid silent WAV and a cancelled replay; this checks native Observation/completion without network, microphone permission or audible speech. Voice cancellation exposes its cleanup task so a sheet cannot release playback ownership while capture still owns resources.

Hosted iOS tests verify the existing archived audio preferences. Native Mac fixtures exercise shared offline settings without changing an answer draft, inline failures, loading cancellation/J, typed-reading autoplay through the final answer and correct/incorrect combined Anki assessment. iPhone/iPad acceptance covers existing offline audio, voice grading/kana correction and subject-detail flows. UI downloads/playback use isolated synthetic data; actual player completion uses the separate silent-file test. These checks do not establish physical-device microphone, route-change or background-interruption acceptance.

The [audio validation receipt](Validation/2026-10-19-shared-audio.json) records exact counts, sources and native bundles. The checkpoint does not publish Mainboard/app commits, run hosted Actions or adopt the native writer on iOS.

The audio acceptance pass corrected a fixture inconsistency: Settings fixtures use a level-1 account, while the old audio stub returned level-24 recordings regardless of the query. The shared filter correctly excluded those future levels. The stub now uses its account's current level. Retry/deletion checks were rerun against clean source; temporary catalog/option tracing was removed. This did not relax subscription or level filtering.
