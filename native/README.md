# Native Mac app

Open `TsurukameMac.xcodeproj` in Xcode 27 and run the `TsurukameMac` scheme on macOS 27 or newer. This is a native SwiftUI app, not Catalyst. The shared `../StudyKit` package has no third-party dependencies.

The Account screen supports a WaniKani API token or clearly labelled synthetic sample data. The app reads statistics and subjects, provides curriculum charts and subject search, and saves an offline snapshot. It has no review/lesson upload endpoints. Reviews, lessons, audio/downloads, full subject mnemonics and settings remain in the iPhone/iPad app during migration.

Credentials use Keychain. The snapshot is saved atomically at `Application Support/TsurukameNative/snapshot-v1.json`, bound to a credential fingerprint. It contains learning progress, not the token. Disconnect removes the credential and snapshot. Sample mode never overwrites the saved account. Sync is manual; each refresh fetches all pages and publishes only a complete result. WaniKani remains the cross-device source of learning progress; iCloud preference/download sync is not implemented.

Build and test:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project native/TsurukameMac.xcodeproj -scheme TsurukameMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path StudyKit
```

A successful build and mock API tests do not establish real-account synchronization, Keychain prompt behavior, or complete desktop interaction coverage. See `../SWIFTUI_MIGRATION.md` for remaining platform work.
