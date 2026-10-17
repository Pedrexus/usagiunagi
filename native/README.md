# usagiunagi · native Mac app

Open `TsurukameMac.xcodeproj` in Xcode 27 and run the `TsurukameMac` scheme on macOS 27 or newer. This is a native SwiftUI app, not Catalyst. The shared `../StudyKit` package has no third-party dependencies and uses Apple SwiftData for local persistence.

The Account screen supports a WaniKani API token or clearly labelled synthetic sample data. The app provides curriculum charts, subject search and an offline snapshot. Saved work shows pending reviews and note edits from this Mac's native store. It can explicitly queue definitively rejected requests and send pending work after account/assignment verification. Uncertain or changed assignments stay saved for further reconciliation. The iPhone/iPad queues remain on those devices. Creating reviews and lessons, audio/downloads, full subject mnemonics and settings still require migration.

Credentials use Keychain. Snapshots are saved in the native SwiftData store at `Application Support/TsurukameNative/study.store`, bound to a credential fingerprint and carrying WaniKani’s stable user ID. The store contains learning data, not tokens. The former `snapshot-v1.json` cache imports once for its matching credential. Its original file is retained for rollback until explicit disconnect, which removes the credential, current snapshot and old cache file. A persistent import receipt prevents deleted snapshots from returning. Old offline snapshots without a user ID remain readable; reconnecting verifies identity before new study-state writes can be enabled. Sample mode never overwrites the saved account. Sync is manual; each refresh fetches all pages and publishes only a complete result. WaniKani remains the cross-device source of learning progress; iCloud preference/download sync is not implemented.

Standalone build and test from the fork root (Mainboard workspace tasks are listed below):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project native/TsurukameMac.xcodeproj -scheme TsurukameMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path StudyKit
```

In `/Users/pedro/Developer/Projects`, use the root Mainboard tasks:

```sh
mainboard run --as-is usagi-build-mac
mainboard run --as-is usagi-test
```

The production store provides atomic session/pending-review persistence and note/synonym revisions for the next study integration. Forty-two persistence test functions pass on macOS and iOS, with 107 shared test functions overall. Separate-process restart checks use the production models. The sample-data flow, charts, coverage drill-down, subject navigation and kanji search were checked in the running Mac app. An isolated synthetic recovery preview verified rejected-request requeuing without sending and preservation of uncertain notes. Build and mock API tests do not establish real-account synchronization or Keychain prompt behavior. See `../SWIFTUI_MIGRATION.md` for remaining platform work.
