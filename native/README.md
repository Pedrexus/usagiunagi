# usagiunagi · native Mac app

Open `TsurukameMac.xcodeproj` in Xcode 27 and run the `TsurukameMac` scheme on macOS 27 or newer. This is a native SwiftUI app, not Catalyst. The shared `../StudyKit` package has no third-party dependencies and uses Apple SwiftData for local persistence.

The Account screen supports a WaniKani API token or clearly labelled synthetic sample data. The app provides curriculum charts, subject search and an offline snapshot. Saved work shows pending reviews and note edits from this Mac's native store. It can explicitly queue definitively rejected requests and send pending work after account/assignment verification. Uncertain or changed assignments stay saved for further reconciliation. The iPhone/iPad queues remain on those devices. The Reviews page now supports offline typed and voice-assisted reviews, wrong-answer feedback, explicit correction, wrap-up and durable pause/resume. Each decision saves with its completed-answer outbox entry before the UI advances. Image-only radicals now render through Apple’s SwiftUI WebView and reuse verified SVG files offline after their first download; missing images can be retried or deferred. Katakana practice and review quick settings also use shared native views. Lessons, audio/downloads, font selection and complete study settings still require migration.

Credentials use Keychain. Snapshots are saved in the native SwiftData store at `Application Support/TsurukameNative/study.store`, bound to a credential fingerprint and carrying WaniKani’s stable user ID. The store contains learning data, not tokens. The former `snapshot-v1.json` cache imports once for its matching credential. Its original file is retained for rollback until explicit disconnect, which removes the credential, current snapshot and old cache file. A persistent import receipt prevents deleted snapshots from returning. Old offline snapshots without a user ID remain readable; reconnecting verifies identity before new study-state writes can be enabled. Sample mode never overwrites the saved account. Sync is manual; each refresh fetches all pages and publishes only a complete result. The shared store coalesces same-account requests and queues an explicit send behind an active read. Closing a waiting window does not cancel an app-owned pass. Disconnect cancels and drains active reads/writes before removing credentials and snapshots; pending work remains account-bound. Late callbacks cannot reconnect the UI. If upload succeeds but refresh fails, the app retains and reports the upload result. WaniKani remains the cross-device source of learning progress; iCloud preference/download sync is not implemented.

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

The production store provides atomic session/pending-review persistence and note/synonym revisions. At the October 18 review-recovery checkpoint, 178 shared Swift Testing functions pass on macOS and iOS (92 persistence, 80 core, 6 speech), and all 73 hosted iOS tests pass. Separate-process checks preserve previous-version pending work across schema upgrades. Native synthetic fixtures verify note resolution, review/lesson comparison, explicit archiving and refresh warnings. Build and mock API tests do not establish real-account synchronization or Keychain prompt behavior. See `../TASKS.md` for exact evidence and remaining platform work.

Native review validation uses a Debug-only `ReviewFixture` launch argument. It creates
one synthetic kanji assignment in an in-memory SwiftData store, bypasses Keychain,
and disables connect, refresh, disconnect and uploads. The fixture is visibly labelled.
It is separate from the statistics sample mode and never changes the normal account
store. Release builds do not recognize the fixture. Test reading `ichi`/`いち` and
meaning `one`, navigation away/back, wrong-answer reveal/correction, completion and
Saved work. Actual microphone/model and real-account upload checks remain separate.

Connected-account subject browsing and review reveals now show full saved
mnemonics/hints, reading labels, local notes/synonyms, bilingual examples and related
subjects in a shared SwiftUI view. Related links stay within the saved account's
accessible catalog. Notes/synonyms can be edited in a shared native form with
revision checks and explicit conflict resolution. Edits enter the local durable
queue; saving does not authorize an upload. Audio, fonts and broader catalog
controls remain tracked. Sample-statistics mode has only summary
content. The synthetic review fixture includes a small linked catalog for UI checks.

Saved work can now compare pending notes/synonyms with WaniKani, then explicitly
keep the local edit queued or adopt the shown server version. Keeping an edit
records a durable server comparison; a changed record stops the next upload and
asks for another decision. Comparing or choosing a version does not send work.
Concurrent changes in another app during a network request can still conflict;
uncertain review/lesson answers use the separate comparison and archive flow below.

For isolated recovery UI checks, launch a Debug build with
`ReviewFixture MaterialRecoveryFixture`. Its notes and GET-only responses are synthetic and
in-memory, and uploads remain disabled. Cancel/close preserves pending work;
keeping a note leaves one queued edit; adopting the server fixture clears that
pending edit and updates the native subject details.

Saved review and lesson answers can be compared with a freshly verified WaniKani
assignment. Keep pending leaves the upload queue intact. An explicit archive choice
moves the exact answer, attempted-state metadata and cached/observed progress into a
durable local archive, with JSON export through the native sharing menu. Archiving
does not submit an answer or establish that WaniKani received it. The subject's old
assignment is removed from the review cache, and statistics require a complete
refresh rather than showing an incomplete schedule. A failed refresh keeps that
warning; successful refresh clears it while preserving the archive.

For isolated review recovery, use `ReviewFixture ReviewRecoveryFixture`; add
`LessonRecoveryFixture` to inspect a lesson. These Debug-only fixtures have
in-memory work and GET-only synthetic responses, with all uploads disabled.
