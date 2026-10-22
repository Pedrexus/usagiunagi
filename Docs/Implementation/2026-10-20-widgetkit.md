# WidgetKit implementation checkpoint

**October 22 correction:** the [Watch voice follow-up](2026-10-22-watch-voice.md) performs
the first Series 12 simulator install. The installer rejects the earlier unpublished
`.watchapp.c.widgets` child under the unified `.watchapp` host. The valid child is now
`com.davidsansome.wanikani.watchapp.widgets`, used consistently by the target and installed
face migrator. Shipping phone/Watch identities and App Group are preserved. Watch targets
now require watchOS 27. The identifiers/deployment wording below describes its historical
source scope; signed registration, upgrade/face migration and delivery remain unaccepted.

Base: `ed45cfe0d45dd38f3fc336d09948fe5cd1aa8836`, branch `codex/swiftui-27-curriculum`. Mainboard: `a2e0e20933b5fda48e4b7402b4f1e6d88d8872b3`. This is production implementation/compiler evidence; no tests, app launches or live exercises occurred. The original-app usability comparison remains deferred until production changes finish.

## Production change

- `WatchWidgets` is a real WidgetKit extension embedded in the existing WatchKit extension's PlugIns, following the installed Xcode watch widget template. It uses Swift 6 and watchOS 9, extension-safe APIs, and the child identifier `com.davidsansome.wanikani.watchapp.c.widgets`.
- One `StaticConfiguration`, kind `StudyComplication`, preserves the global Reviews/Level choice across four accessory families. SwiftUI provides SF Symbols, native text/gauges/progress, relative countdowns, face accenting and matching VoiceOver text. Container background uses Apple's watchOS 10 API when available, retaining the watchOS 9 path.
- The original `LastKnownData` and `DataSource` remain in the original `.watchapp.c` private domain. An atomic binary property-list mirror, `study-complication.plist`, contains only the typed nine-field hint and raw selection. Widget reads never activate transport or access account persistence. Missing/invalid/expired data displays unavailable status. Explicit valid zero stays zero. Historical raw2 directs the person to watch settings; unknown values display the existing default without rewriting them.
- Startup, accepted packets, source changes and migration publish before requesting WidgetCenter reload. Failed writes leave the old shared file intact; migration returns nil if publication fails. No source defaults are deleted or moved. Neither atomic rename nor a successful build proves signed access, power-loss durability or device delivery.
- Incoming age cutoff remains two hours; clock correction does not introduce a new persisted timestamp-ordering rejection. Queue projections retain the due count and accumulate independent full-hour buckets through the 24-hour horizon, checking integer overflow. Future whole-hour entries stop before expiry, followed by an unavailable entry exactly at `max(sent +7200, nextReview)`, including empty/vacation schedules. This deliberately makes the terminal entry and expiry comparison agree. Partial malformed packets do not invent defaults or deadlines.
- Connectivity tasks remain retained through activation, pending-content drain and queued main-actor packet/publication attempts. `hasContentPending` observation, activation callbacks and a DispatchGroup cover those asynchronous paths. Nonactivated/failed activation releases tasks without claiming successful publication. Snapshot tasks retain their native completion behavior.
- ClockKit no longer draws templates or reloads timelines. The original principal class only supplies Apple's static widget migration configuration; its required old current-entry callback returns nil. Fourteen old complication-only asset files and their project references are deleted. The settings hosting scene and original bundle identities remain.

## Build and inventory

Mainboard compile-only action: scheme `Tsurukame`, Debug, generic iOS Simulator, code signing disabled; includes the embedded watch/widget graph. Selected Xcode 27 / Swift 6.4. Final bundle: `.build/Results/build-876eda63aefc48fb95e08a2bad25d3a0.xcresult`. Result: succeeded, zero errors and zero warnings in this incremental build. The untouched hosting storyboard's previously recorded fresh-compilation warning remains outside this claim.

The first migration build exposed a non-Sendable ClockKit configuration crossing the UI actor. The adapter now constructs that configuration in a nonisolated method after awaiting the MainActor's Boolean publication result; no preconcurrency/warning suppression was added. Source review also addressed early background completion, clock rollback, VoiceOver countdown mismatch and unavailable-source guidance. These reviews are not behavioral tests.

Mainboard's current inventory parses 263/263 Swift files, with zero parser gaps and zero project-context issues:

| Category | Files | Physical lines |
| --- | ---: | ---: |
| Production | 142 | 20,487 |
| Tests | 116 | 23,717 |
| Tooling | 5 | 282 |

Compared with `ed45cfe0`: production 20,760 → 20,487, a reduction of 273 physical Swift lines; test/tooling counts unchanged. These are classification counts, including the three preserved off-target owner files, not target-membership or executable-LOC claims.

Ignored report copies: `.build/Reports/WidgetKitInventory.json` (SHA256 `ec64674248ccbbdb09b65d6fa4ee89dc71c2f8325b15a325b67b69c649b02c42`) and `.build/Reports/WidgetKitDiagnostics.json` (SHA256 `173b770cdac2d97df27ebfc9767c67a61e7f06f96c4188937c06ee93c142e736`). Built Info.plists resolve the writer/reader group equally to `group.com.pedrexus.usagiunagi.watch`, and the embedded widget ID matches the migrator setting. This checks configuration, not entitlement authorization.

Frozen production SHA256 values:

```text
d7e50221a275202b6563453b56baa35ce3741812d5f4d0ad72eadf375fcc01e4  App/WatchHelper.swift
0570d85e59e13ebf1295ab961f14c7804db76fdcac942475632816a165b5c9a9  App/ComplicationExtension/ComplicationController.swift
60cbef7b9daace43b432b344951ba776f63a0708a834cc18fa288b091793d85a  App/ComplicationExtension/WatchCompanionCache.swift
ed1a10a210701c87af9a981c7a8a8db2046c13048ddef2beb03cc0425b2ddf46  App/ComplicationExtension/WatchSettingsView.swift
0131faf6b2da98a8e710a1284173d6243243d23c4c07f7c7487b2734c230e4c1  App/ComplicationExtension/ExtensionDelegate.swift
63bad58b361c70240e5de245652e81f49650fe18d078bc67fb31304af0d10b1f  App/ComplicationExtension/Info.plist
a1bfc5e14eba2ceeb4b07b3db580bcf1913a8410ab61088142e89c2f47e85520  App/ComplicationExtension/WatchShared.entitlements
dd82dd451897c064ce58f3c37054f83afdd01f42295c0b9f1616c02c32134bd4  App/WatchWidgets/StudyComplication.swift
15dc2c855e4baee914bce6262277998b0a21a633e8bc9ee59dc6b4ebeefb74bc  App/WatchWidgets/Info.plist
6b1a3d6c9d7d85b68edc277076bbcb8b13a8bdedd82fe89eb5965ec6ca592e45  App/UsagiUnagi.xcodeproj/project.pbxproj
```

## Remaining gates

`USAGI_WATCH_APP_GROUP` is intended configuration, not a registered capability. The owner must register/configure it under the actual signing team and include it in profiles for both the old extension and new widget. No developer-account registration, provisioning, push, PR or distribution occurred. The checked-in upstream team/profiles are not asserted to be usable by the fork.

After production changes and original-app usability comparison, update/run tests for selections, packet validation and clock correction, overflow/horizon/expiry/empty/vacation projections, countdown/VoiceOver, failed/atomic mirror reads and writes, startup/migration before first new packet, repeated startup, rejected packets, activation failures and background/KVO/main-callback ordering. Signed old-face upgrades across all old advertised families, widget gallery/rendering, paired/background delivery and accessibility remain physical gates. The four supported WidgetKit families do not alone prove every old face upgrades.

The retained settings host/single-target lifecycle conversion remains separate. The blocked main-app P0c store-opening draft was not applied or changed by this watch-local cache work. Tests remain deferred under the owner's implementation-first order.

## Watch lifecycle audit, October 21

This is source, installed-SDK and official-documentation review at `25e68d3e`, not an implemented conversion or an upgrade receipt. It does not revise the earlier compiler evidence or the historical main-app P0c status above. No watch source, bundle identifier, provisioning setting or installed data changed during this audit.

Apple's [TN3157](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit) identifies a SwiftUI lifecycle in a single-target watch app as the destination. The widget remains a separate WidgetKit extension. The current content is already `WatchSettingsView`; `SettingsController` only wraps it in `WKHostingController`, and `App/Complication/Base.lproj/Interface.storyboard` contains an empty host scene. Removing that wrapper alone does not consolidate the executable targets or prove data continuity.

### Installed SDK constraints

The selected Xcode 27 WatchOS SDK's `SwiftUI.swiftmodule/arm64_32-apple-watchos.swiftinterface` declares `WKExtensionDelegateAdaptor` for an `NSObject` conforming to `WKExtensionDelegate`, introduced in watchOS 7 and deprecated in 9.2. `WKApplicationDelegateAdaptor` instead requires `WKApplicationDelegate` and is available from watchOS 7. Apple's [extension adaptor documentation](https://developer.apple.com/documentation/swiftui/wkextensiondelegateadaptor) explicitly describes an extension using the SwiftUI lifecycle and one adaptor declared in its `App`; the [application delegate documentation](https://developer.apple.com/documentation/watchkit/wkapplicationdelegate) describes the single-target app. These are different lifecycle owners, not interchangeable annotations selected only by availability.

The installed `XCBuild.framework/.../XCBSpecifications.ideplugin/Contents/Resources/watchOSShared.xcspec` marks `com.apple.product-type.watchkit2-extension` as an error when the deployment target is watchOS/watchSimulator 9.2 or later. Its inherited linker entry is `_WKExtensionMain`. The existing watch targets deploy to 9.0. Raising the old extension's deployment target to 27 is not a migration and encounters this product constraint. Neither the API signatures nor a successful compile establish that changing the current executable entry/launch path is safe; a lifecycle change needs actual cold-launch evidence.

### Optional deprecated dual-target stage

A narrowly scoped intermediate change could put an `@main App` in the existing `.watchapp.c` extension's Sources, use exactly one `@WKExtensionDelegateAdaptor(ExtensionDelegate.self)`, and host `WatchSettingsView` in its `WindowGroup`. It would remove `SettingsController`, the empty storyboard/resource reference and obsolete `IBSC_MODULE`. The legacy `WKExtensionDelegateClassName` registration would need removal so the adaptor is the sole intended delegate owner. Keep the existing extension point and watch-app relationship, ClockKit principal class, custom group/widget metadata, entitlements, widget embedding and all current bundle identifiers unchanged. Do not add the widget's separate `@main` source to this target or invent a linker-entry override.

This stage keeps the `.watchapp.c` executable and private-defaults identity structurally intact; it therefore avoids introducing the final collapse's cross-domain transfer. It still needs a compile, cold launch, proof that `Bundle.main` is the expected extension, preserved defaults and exactly one lifecycle/transport owner. It retains a deprecated adaptor, delegate and extension product, cannot support a 9.2+ deployment target in that graph, and does not complete the requested single-target modernization. It is an optional reversible stage, not the final answer.

### Final single-target destination and identity boundary

The smallest final conversion would convert the existing watch-app target in place into a normal watch application, move the extension's sources/privacy resource and required configuration into it, use an `@main App` with [`WKApplicationDelegateAdaptor`](https://developer.apple.com/documentation/swiftui/wkapplicationdelegateadaptor) and `WKApplicationDelegate`, and remove the old extension target and storyboard host. Move the widget dependency/embedding from the extension to the watch app. Move the ClockKit principal-class and custom group/widget identifiers to the application configuration, retain its migration-only implementation, and apply the authorized App Group entitlement to the actual writer and widget reader. The iOS embed and existing watch-app scheme can continue to reference the retained watch-app target; their built products and launch behavior still require verification.

Keep the shipping iOS `com.davidsansome.wanikani` and Watch app `com.davidsansome.wanikani.watchapp` identities unless the owner approves a separate change. The new unpublished widget uses the installer-valid `com.davidsansome.wanikani.watchapp.widgets` child, as corrected above. The `.watchapp.c` extension necessarily ceases to be an active executable if that target is removed. Preserving its historical data is therefore a separate requirement; retaining every old executable bundle identity and removing that executable are not the same operation. Changing the surviving Watch app's identifier to `.watchapp.c` must not be used as a shortcut without explicit approval and installed-upgrade proof. Signed registration/publication and installed-upgrade acceptance still require their separate gates.

Retain the existing one-time startup guard, WatchConnectivity receiver and background-task completion semantics during the lifecycle conversion. A separate adoption of SwiftUI's newer background-task modifiers is unnecessary for the minimal migration and must not create a second completion owner. Keep the wire keys, packet validation, projections, WidgetKit kind and migration widget identifier stable.

### Concrete private-defaults and mirror overwrite hazard

`WatchCompanionCache.state` currently reads `DataSource` and `LastKnownData` only from `UserDefaults.standard` (`App/ComplicationExtension/WatchCompanionCache.swift:107`). `ExtensionDelegate.applicationDidFinishLaunching` immediately calls `WatchHelper.reloadComplications` before a phone packet arrives (`ExtensionDelegate.swift:24`); that path atomically publishes the current standard-default state. The ClockKit migrator also publishes before returning a widget configuration (`ComplicationController.swift:38`), so it can reach publication independently of the settings UI.

If a collapsed app starts in a new private domain without those values, the current integer lookup returns Reviews (`0`) and the snapshot is nil. Unchanged startup would replace a valid shared `study-complication.plist` with that empty state. An atomic write does not prevent this logical data loss. A migration must restore or verify the authoritative prior state before **any** first publication, including a migration callback, rather than wait for the settings view or the next phone message. It must distinguish an absent key from an explicitly saved Reviews value.

The App Group mirror can help only when a prior installed version actually wrote it and the new signed app has access. An upgrade that skips this WidgetKit checkpoint may have only `.watchapp.c` private defaults. The retrieved Apple conversion/delegate documentation does not establish that removing this project's extension transfers its private defaults into the new app, or that opening `UserDefaults(suiteName: oldBundleIdentifier)` grants access to the removed extension's container. Do not assume either. Prove a supported transfer/retention path with the actual converted and signed product before shipping the collapse; an unavailable path remains a blocker, not permission to silently reset or delete settings.

Preserve the exact raw `DataSource`, including historical `2` and unknown values, and the complete valid `LastKnownData` packet. An old packet may correctly produce stale/unavailable rendering while still retaining the original Last Updated information. The incoming-message two-hour cutoff is not a reason to discard historical saved state during upgrade. No automatic legacy-default deletion is proposed.

### Required acceptance before final retirement

| Gate | Required evidence |
| --- | --- |
| Signed identity and access | Actual team/profile authorization for the surviving app/widget identifiers and App Group; verify the installed executable and reader/writer entitlements. Checked-in upstream profiles and unsigned builds do not grant those rights. |
| Skip-version state continuity | Upgrade a same-identity signed original private-defaults-only installation directly to the candidate, and also upgrade through the mirror-writing version, with no new phone packet. Verify exact source values (`0`, `1`, legacy `2`, unknown), valid zero counts, complete/stale saved packets and Last Updated. Verify first startup and direct migrator publication cannot replace preserved state with empty defaults. |
| Lifecycle and settings | Cold launch, repeated launch, settings navigation/picker/reopen, VoiceOver and accessibility; demonstrate one delegate and one receiver owner and the expected executable/defaults identity. |
| Installed faces | Exercise all historically advertised ClockKit families through the installed migration, including the default descriptor case; verify the principal-class lookup, unchanged kind/widget identifier, gallery availability and the actual resulting face layouts. Four new accessory families alone are insufficient evidence. |
| Background transport | Paired real-device delivery, activation failure/retry, pending-content/KVO drain and queued main-actor packet publication before completion; retain snapshot-task completion behavior and verify rejected packets do not erase saved data. |
| Packaging and deployment | Verify final target/product membership, one app entry per executable, widget embedding, configuration/entitlements and supported deployment target; compile and cold-launch the actual final graph. |

These are pending acceptance requirements, not results. A compiler pass can establish source/package compatibility, but cannot establish private-data continuity, installed-face replacement or paired/background delivery. No final single-target conversion is accepted by this document.

## Primary references

- [Apple: Migrating ClockKit complications to WidgetKit](https://developer.apple.com/documentation/widgetkit/converting-a-clockkit-app)
- [Apple: Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: Watch connectivity background tasks](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask)
- [Apple: Updating watch projects for SwiftUI and WidgetKit](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)
- [Apple: iOS/iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes): the WidgetKit `transferCurrentComplicationUserInfo` issue is listed as **fixed** (113202790/FB12819178); the existing iOS27 sender is retained.

The installed Xcode template at `Platforms/WatchOS.platform/Developer/Library/Xcode/Templates/Project Templates/watchOS/Base/Watch App Extension Base.xctemplate/TemplateInfo.plist` establishes the retained extension as an allowed widget host. Its widget template and generic App Extension Base establish the extension product, embedding and child bundle prefix.

## October 21 launch handoff trial

The settings source comparison found no additional missing control. The remaining storyboard host warranted a bounded compiler/artifact experiment, preserving all production bundle identifiers, defaults keys, App Groups and transport methods. The candidate added a SwiftUI `App` with `WKApplicationDelegateAdaptor`, kept the existing delegate callbacks, and removed the hosting controller/storyboard and delegate plist key. No app or account was launched.

The candidate builds for both watch simulator architectures with zero compiler errors/warnings: `build-c42ef51ff21d4e9481a2c785feb1b667.xcresult`, diagnostics SHA `6a516e0f9caa9e022ed44f8d96a52159a8135316adcc48cd08eb4db07a828162`. Both actual link commands still specify `-e _WKExtensionMain`. Mainboard `apple bundle` on the candidate watch extension, with `--forbid-symbol _WKExtensionMain --json`, exits 1 and reports the legacy symbol in the extension. Its two packaged binaries are inspected; report SHA `a0872ce14669b823b37821ecd595c88dc68114efacd9db53cd1c74faf2026a41` at `.build/Reports/WatchLifecycleCandidateBundle.json`. This diagnostic policy rejects an unestablished modern launch handoff; it does not prove an observed launch failure.

The full candidate was reverted before committing. Its proposed app source and tracked-file patch remain only in ignored `.build/Reports/WatchLifecycleCandidate.swift` and `WatchLifecycleCandidate.patch`, respectively SHAs `66ccae0fb646f7aba8380315fc37e225379e69f747e02f6113b9ece281a5b42d` and `a7ec52510a1d48cc85d915ba84d658ef665a939cf8025f55258ec991893bbcf2`. Candidate build log SHA is `738b85a634ee8579bd16b03b493b96317b98e88cef33f2c5299fbcb28739382d`. These files are evidence, not an applied migration or app-local tool. The unretained inventory also remains explicitly separate.

Restored production sources match `f956074f`, apart from the three unchanged protected owner edits. The current iOS Release rebuild passes with exactly the existing WatchKit storyboard warning: `build-e951b2e4f362462ab6034d5177b63d93.xcresult`, diagnostics SHA `047d774fa25cdef561bf9184420b967f0f85888e42eea6e61c53f273f23b5c01`. The maintained iOS bundle audit passes on all five packaged Mach-O files; `.build/Results/WatchLifecycleRestoredBundle.json` SHA `ad78cbcf6cfe363cc61682f92166f65e9df06e0d4443e2d3c75847fa6791ed2c`. Restored Mainboard inventory parses 259 files with zero gaps/context issues: 145 production files/21,582 physical Swift lines, 109 test files/25,310 lines and five tooling files/281 lines. Report SHA `915782bdb1497d75cc51e2821d1b241a8e624b706c7d4d3af9491e221b71eade` at `.build/Reports/WatchLifecycleRestoredInventory.json`. No new test-suite or rendered acceptance is claimed.

[Apple's single-target migration guide](https://developer.apple.com/documentation/watchos-apps/migrating-to-a-single-target-watchos-app) requires the full target/resource/delegate conversion and verification on a watch; a watchOS 9.2+ minimum deployment target also rejects dual-target packaging. [TN3157](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit) distinguishes that conversion, SwiftUI lifecycle adoption and installed-face migration. The remaining work must establish the launch path and private defaults/container continuity together, retain the WidgetKit face migrator, and verify signed upgrades/background delivery before deleting the existing packaging. A compiler-only change is insufficient. There is no new entry-point override, signing/identifier change, UIKit screen, platform utility or deployed product in this checkpoint.
