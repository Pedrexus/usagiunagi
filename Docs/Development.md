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

## Automatic native sync acceptance

Shared Swift Testing now exercises automatic review/note sending, offline restoration, a newer edit arriving during an in-flight write, lost replies, fresh vacation/access metadata, throttling, authorization pauses and disconnect/reconnect draining. The upload-only lane is checked separately from a queued full read. Existing import tests continue to require newer verified snapshot metadata and legacy references to survive. Native Mac acceptance completes a review and verifies an empty Home queue/Saved work without pressing Sync; separate recovery acceptance keeps an uncertain answer pending and performs only comparison. All network operations in this UI fixture are typed in-memory simulations. Core transport tests continue to validate real HTTP response shapes.

Use the existing Mainboard shared/hosted tasks and native test classes. Actions already selects the full classes, so the new functions need no app-local driver, new task alias or separate CI job. The [validation receipt](Validation/2026-10-20-automatic-native-sync.json) records the exact source/test/build scope and remaining read/physical-device gates. This feature addition grows production code before legacy-writer retirement; it is not a LOC reduction or a complete iOS migration.

## Notification acceptance

The existing `usagi-test-settings` and `usagi-test-settings-ipad` gates now retain all three original settings cases and add `testSharedNotificationSettingsPersistWithoutSystemPrompts`. The standalone Actions workflow already selects the complete ReviewFlowTests and native Mac test classes, so it discovers the new notification cases without a separate job. Tool publication/hosted CI is still pending owner-authorized pushes.

Shared Swift Testing covers exact/DST scheduling, capability and preference combinations, the shared pending-request budget, stale reads/adds, per-window notices, independent System Settings returns and later-disabled choices. Hosted tests preserve the iOS Boolean archive contract and use a nil watch session for duplicate/clock/logout packet checks. Native acceptance uses an injected client for every notification operation: no real OS permission prompt, badge change, scheduled alert, WaniKani exercise or account edit is part of this evidence. Actual signed-device notification delivery, paired watch handoff and physical permission flows remain acceptance gates. Sample-data release launch probes pass no notification service into the root.

## Source and resources

`Shared/Package.swift` remains the authoritative shared dependency manifest. App package locks and `App/Podfile.lock` remain committed. FMDB, Reachability, SwiftGen and Hippolyte still serve active iOS migration callers; Mac's runtime has no CocoaPods dependency. Both app CI jobs restore the unified project's generated integration/file lists before building. `pod install` preserves a post-integration guard so iOS framework hooks do not run for the native Mac destination.

App-specific generators are in `Resources/Generators`; the legacy protobuf schema is beside `App/WaniKaniAPI/Schema`; the production persistence executable is in `App/Tests/PersistenceProbe`. The Swift Testing suites live with Shared, hosted integration suites with App, and XCUITest remains appropriate for actual UI interactions.

CircleCI, upstream Fastlane publishing/signing, unused snapshot capture, Xcode Cloud release notes, obsolete store screenshots and upstream Firebase deployment were retired. Generated Pods/build caches are ignored. Fonts and historical link-association references are retained under Resources/Hosted. Previous result logs/screenshots remain under ignored `.build/Previous`; durable receipts remain in Docs/Validation. No command deploys to the original author's account.

The [levels 1–3 display preview](../Resources/Fixtures/README.md) contains 357 real catalog references read from WaniKani's visible level pages without an API token. Mainboard exported `Resources/Fixtures/free-levels.parquet` with Zstandard; the app reads matching binary Apple property-list data through Foundation. Mac Account → Preview free levels 1–3 opens it offline, with negative local IDs, no assignments/account identity and no uploads. These are display readings/meanings, not full accepted-answer rules, mnemonics or real WaniKani IDs. Complete review/lesson fixtures still require an authorized API catalog. Chrome was returned to the dashboard and no exercises or account changes were made.

## Typed subject fixture and Home acceptance

The existing `usagi-test-home` and `usagi-test-home-ipad` tasks cover the common grouped Home, availability, forecast, typed reviews, lessons, catalog navigation and inline Coverage. Native Mac acceptance uses the existing Home/forecast/search and lesson pause/resume cases; app-window screenshots show both light and dark native grouped sections. The initial grouped-layout gates ran before a screenshot-driven foreground-contrast correction; final Home/rotation checks rerun that presentation on all platforms, with the full typed-fixture and database changes unchanged. The original 60 synthetic subjects now use typed Swift construction rather than runtime protobuf-text parsing. A one-time local comparison verifies equality and identical serialized bytes against the evaluated original Swift literals; it does not require a live account. The existing response/recovery fixtures and active iOS SQL remain necessary until their callers are replaced. Exact source hashes, test results and physical LOC scopes are in the [cleanup receipt](Validation/2026-10-20-typed-fixtures-home.json).

## Font acceptance

Shared font tests use isolated preferences/directories and local URLProtocol responses to check activation, glyph filtering, stale completion/cancellation, failure/retry and cache preservation. Hosted iOS tests additionally activate the eight original font files and verify the existing archived selection format. Native UI fixtures use the installed Japanese PostScript name `HiraMinProN-W3`; a nonexistent family name silently falls back to Helvetica on Mac and is not a valid Japanese test font. Fixture networking is local, delayed and cancellable; no live WaniKani exercises are used.

The shared library keeps network work outside UI state and publishes completion on MainActor. The debug URLProtocol fixture uses a mutex for its cancellation flag across the Foundation callback queue; it does not weaken production actor isolation. See the [official Swift sending-closure diagnostic](https://docs.swift.org/latest/documentation/diagnostics/sending-closure-risks-data-race/) and the [font checkpoint receipt](Validation/2026-10-19-shared-fonts.json).

## Audio acceptance

Shared tests cover voice/cache selection, subscription priority, cancellation/account changes, retained preferences and explicit deletion. The real AVFoundation backend is tested with a corrupt local file followed by a valid silent WAV and a cancelled replay; this checks native Observation/completion without network, microphone permission or audible speech. Voice cancellation exposes its cleanup task so a sheet cannot release playback ownership while capture still owns resources.

Hosted iOS tests verify the existing archived audio preferences. Native Mac fixtures exercise shared offline settings without changing an answer draft, inline failures, loading cancellation/J, typed-reading autoplay through the final answer and correct/incorrect combined Anki assessment. iPhone/iPad acceptance covers existing offline audio, voice grading/kana correction and subject-detail flows. UI downloads/playback use isolated synthetic data; actual player completion uses the separate silent-file test. These checks do not establish physical-device microphone, route-change or background-interruption acceptance.

The [audio validation receipt](Validation/2026-10-19-shared-audio.json) records exact counts, sources and native bundles. The checkpoint does not publish Mainboard/app commits, run hosted Actions or adopt the native writer on iOS.

The audio acceptance pass corrected a fixture inconsistency: Settings fixtures use a level-1 account, while the old audio stub returned level-24 recordings regardless of the query. The shared filter correctly excluded those future levels. The stub now uses its account's current level. Retry/deletion checks were rerun against clean source; temporary catalog/option tracing was removed. This did not relax subscription or level filtering.

The obsolete developer/TestFlight/store configuration enum and its custom compilation macros are removed. Standard `DEBUG` keeps the existing optional practice entry points out of Release builds. Saved-work fields use default SwiftUI labeled-content accessibility; custom child-hiding and whole-row selection suppressed their values on native Mac. Native acceptance verifies the exact current stage and preserves the uncertain answer after closing comparison.

## Recoverable cold handoff acceptance

The [existing persistence probe](../App/Tests/PersistenceProbe/README.md) now includes import/credential/activation and rollback checkpoints. The existing shared Actions job runs them through Mainboard's bounded process tool, requires the deliberate exit code 86 and rejects timeouts or unexpected success. No new app Tools driver or root task is introduced. The same executable still checks original outbox and catalog restart behavior; its synthetic server uses typed Swift instead of raw JSON. Invalid probe arguments exit nonzero.

The importer suite now uses Swift Testing for all eight existing behaviors and a new parameterized real schema 9–15 bootstrap/reopen check. It retains malformed/protobuf/WAL and grading-input checks and uses per-test disposable directories. Handoff unit coverage includes credential failures before/after a save, discarded saves, source/token changes, another credential, concurrent scenes, cancelled waiters, rollback, missing prepared snapshots and one-way selection after logout. The account verifier has only the read-only account capability. Fresh verified profile propagation reuses the same helper as native uploads; credential fingerprints retain their existing bytes.

The [validation receipt](Validation/2026-10-20-native-bootstrap.json) separates these synthetic process/schema results from real Keychain, signed-device and production-scene acceptance. Writer integration is still gated on remaining settings/companion/background parity. The prepared workflow and unpublished Mainboard dependency have not been pushed or run on hosted Actions.

## Shared companion acceptance

The watch's typed forecast/level projection and queue/duplicate tests now run in shared Swift Testing on Mac and iOS. The actual phone bridge checks all existing wire keys/value types. Notification tests cover companion updates before blocked notification I/O, stale account reads, read failures and permission checks without an account source. Existing phone/iPad notification UI acceptance uses isolated notification and companion clients; no real OS prompt, watch activation or live account write is part of that evidence.

The retained watch target is built through Mainboard with scheme `Tsurukame Complication` and destination `generic/platform=watchOS Simulator`; the iPhone Actions job now includes this gate. Framework deprecation warnings remain. Its WatchKit/ClockKit UI and character placeholder still need modernization; a build does not prove physical paired delivery or native iOS root adoption.

Serialize all test processes using the same simulator, including unhosted shared tests and hosted integration. A concurrent local run ended with a test bootstrap SIGKILL and failed simulator diagnostics; the isolated rerun passes, without a product workaround or disabled check. The cause is not proven. Native GUI acceptance also runs one platform at a time; independent builds may use separate derived-data directories. The [validation receipt](Validation/2026-10-20-shared-companion.json) records the exact results and this failed-run limit. No hosted Actions pass or tool/app push is claimed.

The current native Mac UI gate could not start: both isolated attempts timed out enabling automation before the app launched. Mac Release builds and shared tests pass; native Mac UI behavior at this checkpoint is unverified. No automation/security settings were changed.

## Native reference catalogs

Curriculum, levels 1–3 display references, old mnemonics and similar-kanji data ship as binary Apple property lists. One Foundation Codable loader replaces three repeated file/JSON loaders. The conversion compares every original serialized value, preserving metadata, Unicode and ordered arrays. The four catalog files shrink from 364,140 to 220,778 bytes; the mnemonic file alone grows slightly, so this is the total, not a claim that every file shrinks.

Generators write binary data directly to a named file and log text summaries through Mainboard. Binary stdout cannot safely pass through text log capture. Curriculum regeneration matches the current catalog exactly. The similar-kanji generator retains its original decoded output, which already differs from the bundled historical ordering; that snapshot is preserved rather than silently refreshed. See [source procedure](../Resources/Generators/SimilarKanji/README.md).

Review/practice navigation now shares one host setup while keeping each existing scope's filter, scheduled-review ordering/limit and shuffled practice policy. Recent lessons/mistakes share their identical review-stage selector. Home presentation still uses the common grouped Form, WaniKani subject colors and glass study actions; this checkpoint introduces no new design. Production Swift falls 30 physical lines (30,216 → 30,186), including the new loader and formatting of the touched curriculum file. Reference-data lines are not counted as removed Swift code. API/archive JSON, acceptance fixtures and the current iOS SQLite writer remain necessary; their removal is gated by compatibility and the documented writer handoff.

Exact checks, source/resource hashes, conversion and generator limits are in [native catalog validation](Validation/2026-10-20-native-catalogs.json). Mac GUI acceptance remains pending the automation startup failure recorded in the companion checkpoint; current resource/test/build acceptance does not turn it into a UI pass.

## Common settings acceptance

The existing phone/iPad settings cases cover the common menu, lesson/review choices, appearance/email and subject preferences, isolated notification toggles and cancellation of pending-work logout. The disconnected-host regression now reads the consolidated account state and also requires an empty avatar. The old app hashing extension/test are removed; three parameterized shared tests verify the actual Gravatar normalization, fallback and exact request/cache URL at all three original image sizes. Shared suites total 422; hosted integration totals 92 after replacing the one SDK-only digest function.

Native UI tests use the common stable menu identifiers. The existing notification case now includes appearance/email persistence, without forcing a fixture color scheme. The current runner failed before app launch; a direct synthetic-app check separately observed settings navigation, persisted Dark/email/reminder values, actual Light rendering, matching review appearance and return Home. No native XCUITest pass, active-window accent verification, physical permission result or complete iOS root adoption is inferred. No security/automation settings were changed. See [exact settings results](Validation/2026-10-20-shared-settings.json).

## Common review-policy acceptance

The shared queue tests preserve all original order/raw-value contracts, random ties, projection count and post-sort caps. Store tests cover unchanged paused work, uncapped Home/practice, consistent leech thresholds, cached custom SRS intervals across process-store reopening, old account decoding and atomic rejection of invalid metadata. Download tests exercise all six documented interval units and malformed/missing definitions. Typed test fixtures stay in test support; runtime catalogs do not gain hardcoded JSON.

The touched review-preference archive suite now uses Swift Testing, retains/restores every original archive and checks session options, ordering codes, fieldwise updates and Anki transitions. Existing iPhone/iPad UI acceptance follows the shared Answer mode control, plus font/audio routes and representative typed/practice flows. Native Mac direct observations remain separate from the previously failing automated runner. See [review-policy validation](Validation/2026-10-20-review-policy.json) for exact final results and source hashes.

Prefer the declared Mainboard Apple tasks. For an ad hoc nested executor, pass `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` directly to its Apple command to select the build/result toolchain. The current iPad assertion failure also produced an internal Xcode simulator-diagnostic `simctl` warning despite that explicit environment; its cause is unresolved. This does not hide the actual UI assertion or invalidate the retained result bundle. Use `mainboard apple results` on that exact failed bundle to inspect its counts/failure. The earlier suggestion that passing the variable alone fixed this warning was not established.

## SwiftUI settings navigation acceptance

The existing font cases now exercise both Back to quick settings and Done directly to an unchanged answer, retaining selection, cancellation/retry, deletion and continued-download assertions. The full settings cases still cover every main destination and safe logout cancellation. Developer endpoint validation/reset/cache/export and audio settings/download/failure cases verify the destinations after the controller wrappers are removed. They run with isolated synthetic accounts on phone and iPad, serialized through Mainboard.

The native Mac direct check opened an unanswered synthetic review, kept the unsubmitted `みほん` draft through Fonts and Offline Audio, observed retained installed-font selection, Back to Quick settings and Done from both media pages. The own-sheet screenshot shows the reduced quick-settings form. No answer was submitted and no live account was accessed. This is distinct from the previously failing Mac XCUITest runner. Exact final results, source hashes and the net Swift line count are in [settings-navigation validation](Validation/2026-10-20-settings-navigation.json).

## Preference and media handoff acceptance

Disposable defaults tests cover actual keyed archives, raw values, all preference groups, missing old defaults, unknown/malformed values, source byte preservation, account-bound avatar fallback and existing native edits. Hosted tests exercise the same cold source adapter across actual SQLite schemas 9–15. No real token enters the receipt or test evidence. The shared bootstrap tests also verify endpoint selection, changed-source rejection and old activated receipts.

The existing persistence executable now stops after the durable writer choice but before the first native preference write, using a disposable defaults subclass in the probe only. A fresh process hydrates preferences from the receipt without retired source/network/credential reads and then preserves native work through logout/reopen. The Actions gate requires each exact checkpoint text as well as exit 86. This is local separate-process evidence; hosted Actions and actual Keychain/signed-device upgrades remain unverified. See [preference-handoff validation](Validation/2026-10-20-preference-handoff.json).

## Native cleanup acceptance

The synthetic statistics generator is test support only. The production app has one offline browsing preview, with no launch-argument branch for invented progress. The existing Mac fixture now supplies its historical pace through typed in-memory account data, retaining the exact 1.8-day/five-level validation expectation. UI tests use native tabs on every platform; a rejected sidebar/header prototype is not part of the change.

Similar-kanji source conversion compares all decoded JSON values with the property-list round trip, then compares the former and current generator’s entire `[String: String]` output, including Unicode candidate ordering. PropertyListDecoder requires exact Float representation for stored numbers; reading the original Double precision and applying the old Float rounding explicitly preserves the existing scoring behavior. The app’s bundled catalog is checked against HEAD and is not regenerated by this cleanup. See [native-cleanup validation](Validation/2026-10-20-native-cleanup.json).

Final native Mac observations used only the isolated synthetic service: Home/Stats tabs, eight pace values, the unchanged 1.8-day/five-level check, inline expansion and pause/resume with the unsubmitted `みほん` draft at 0 completed/1 remaining. The own-window screenshot excludes the desktop. This does not claim a Mac XCUITest pass; the previously failing runner and physical-device gates remain open.

## Automatic catalog read acceptance

Mainboard’s shared suites now cover fresh/stale foreground caches, post-study new unlocks, preserved session revisions, uncertainty without replay, multiple scenes/background deferral, failed-read recovery, durable rate limits, account cancellation, clock rollback and a fresh worker discovering an earlier study request. Persistence tests reopen a durable acknowledged-work marker and interleave reads with newer attempt/acknowledgement markers. Existing grading, outbox and schema importer tests remain enabled.

A disposable archive of exact commit `70414fb6` builds the old persistence writer through Mainboard. Its catalog store is then opened by the current probe, which explicitly verifies the absent optional marker and retained profile, catalog, assignment and pending note. The normal separate-process restart checks and all handoff crash/rollback phases still pass; no real Keychain or live account is used.

Direct Mac inspection uses the DEBUG-only in-memory service, completes one synthetic review and returns to Stats. Its cached snapshot stays at 6:11 until the automatic read updates it to 6:12, without using Refresh. The fixture timestamps each typed download like the production client. The saved own-window screenshot and AX states establish integration and a real timer event, not exact timer latency or a Mac XCUITest pass. The fixture is closed afterwards. Current results and source hashes are in [automatic-read validation](Validation/2026-10-20-automatic-catalog-reads.json).

## Service ownership and compact Home acceptance

The existing Mainboard shared and hosted suites cover app-owned restoration, cancellation/disconnect fencing, windowless notification/companion publication, lesson visibility, blocked network/system I/O and confirmed-work sync. The common native assembly is compiled on iOS without activating a second writer. No new app-local executor or task alias is added. Background OS scheduling/deadlines remain a production integration gate.

Existing Home and Katakana cases cover the compact shared list, rotation, refresh, empty/vacation queues and typed/Anki practice on iPhone and iPad. Native lists create off-screen rows lazily, so the vacation assertion scrolls to its unchanged progress value. Its first failure and corrected rerun are retained in the receipt. Mac window inspection checks the real synthetic app's primary navigation and paused review. Release scans verify the tested fixture switches are absent. See [the cleanup receipt](Validation/2026-10-20-service-and-ui-cleanup.json) for exact source hashes, counts, builds and limitations.
