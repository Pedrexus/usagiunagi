# usagiunagi · native Mac app

Open `TsurukameMac.xcodeproj` in Xcode 27 and run the `TsurukameMac` scheme on macOS 27 or newer. This is a native SwiftUI app, not Catalyst. The shared `../StudyKit` package has no third-party dependencies and uses Apple SwiftData for local persistence.

The Account screen supports a WaniKani API token or clearly labelled synthetic sample data. The app reads statistics and subjects, provides curriculum charts and subject search, and saves an offline snapshot. It has no review/lesson upload endpoints. Reviews, lessons, audio/downloads, full subject mnemonics and settings remain in the iPhone/iPad app during migration.

Credentials use Keychain. Snapshots are saved in the native SwiftData store at `Application Support/TsurukameNative/study.store`, bound to a credential fingerprint and carrying WaniKani’s stable user ID. The store contains learning data, not tokens. The former `snapshot-v1.json` cache imports once for its matching credential. Its original file is retained for rollback until explicit disconnect, which removes the credential, current snapshot and old cache file. A persistent import receipt prevents deleted snapshots from returning. Old offline snapshots without a user ID remain readable; reconnecting verifies identity before new study-state writes can be enabled. Sample mode never overwrites the saved account. Sync is manual; each refresh fetches all pages and publishes only a complete result. WaniKani remains the cross-device source of learning progress; iCloud preference/download sync is not implemented.

Build and test:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project native/TsurukameMac.xcodeproj -scheme TsurukameMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path StudyKit
```

The production store also provides atomic session/pending-review persistence and note/synonym revisions for the next study integration; this Mac UI does not yet expose review/lesson uploads. Twelve persistence tests pass on both macOS and iOS, and a separate-process restart check uses the production models. The sample-data flow, charts, coverage drill-down, subject navigation and kanji search were checked in the running Mac app; sample statistics were checked again after the native-store build. Build and mock API tests do not establish real-account synchronization or Keychain prompt behavior. See `../SWIFTUI_MIGRATION.md` for remaining platform work.
