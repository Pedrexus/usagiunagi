# WidgetKit implementation checkpoint

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

## Primary references

- [Apple: Migrating ClockKit complications to WidgetKit](https://developer.apple.com/documentation/widgetkit/converting-a-clockkit-app)
- [Apple: Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: Watch connectivity background tasks](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask)
- [Apple: Updating watch projects for SwiftUI and WidgetKit](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)
- [Apple: iOS/iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes): the WidgetKit `transferCurrentComplicationUserInfo` issue is listed as **fixed** (113202790/FB12819178); the existing iOS27 sender is retained.

The installed Xcode template at `Platforms/WatchOS.platform/Developer/Library/Xcode/Templates/Project Templates/watchOS/Base/Watch App Extension Base.xctemplate/TemplateInfo.plist` establishes the retained extension as an allowed widget host. Its widget template and generic App Extension Base establish the extension product, embedding and child bundle prefix.
