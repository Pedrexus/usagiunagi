# App module consolidation

The app now owns its SwiftUI features and voice implementation. StudyCore and StudyPersistence retain their existing nominal identities because the main persisted schema and Codable payloads depend on them. No main-store declaration or decoder was changed.

## Preference model module move

The exact existing `PrivatePreferencesV1` declaration was compiled in two separate executables, with module names `StudyUI` and `Tsurukame`, using installed Apple Swift 6.4 and macOS 27 through Mainboard. The original module wrote one synthetic preference change; a separate process using the new module reopened that store and verified all five stored fields plus the unchanged persistent identifier (store UUID, entity and primary key).

The synthetic store, stable identity, source archive, checksums and successful read receipt are preserved in `App/Tests/PersistenceProbe/Fixtures/private-preferences-module-move`. Unzip the source archive to a temporary directory, build through `mainboard run --locked --no-install mainboard proc timeout 180 /usr/bin/xcrun swift build --package-path <directory>` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, then run the built `Tsurukame read <fixture-directory>` through the same bounded Mainboard runner. Use a disposable copy of the fixture. For a fresh independent writer, run the built `StudyUI write <empty-directory>` before the reader.

This is a populated local-store module-identity check, not a signed CloudKit delivery or production-server schema qualification. The signed iCloud gate remains open. The schema uses scalar properties, unlike the main store's module-qualified Codable payload graph.

The initial probe compared raw JSON bytes for the persistent identifier and failed because encoder key order differed. The corrected probe decodes `PersistentIdentifier` and compares typed equality; the original record values had already matched. No production behavior was changed to satisfy the probe.

## Transferred implementation and tests

Sixty Swift implementation files moved from StudyUI and StudySpeech into App feature folders, including the existing UI bridges. The three voice files are in `App/Reviews/Voice`. The font preview asset catalog belongs to the app bundle. Nine test files moved into AppTests, using the existing three shared test-support source files without a new library. The existing hosted AppTests lanes cover their tests; pure Core/Persistence tests remain in the package lane.

The app target now has the same default MainActor isolation as the former UI module, with the existing upcoming strict-concurrency settings. Its actor-owned speech capture remains actor-isolated. The shared Watch connectivity delegate uses the explicit `any Error` existential required by the inherited language setting. The account-restore error now describes account restoration, covering credential reads as well as cached account data.

Validation results are recorded after the build and hosted test compilation complete. No UI automation is run as part of this move; the user's normal simulator session is preserved.

## Results

- iPhone build-for-testing: `build-for-testing-29d527fe9efe49d4aef132d01e76e54b.xcresult`, succeeded with zero warnings/errors. All hosted test sources compiled without launching the simulator.
- Native Mac build-for-testing: `build-for-testing-33064d5965434538906b6b36368feb67.xcresult`, succeeded with zero warnings/errors.
- All nine transferred Mac hosted suites: `test-25043c9b94ae44078a1f3e8b0364f131.xcresult`, 126 functions / 163 parameterized executions passed, zero failures, skips or runtime warnings. These cover account restoration, API endpoint changes, synchronization, iCloud preference conflict/reopen behavior, notification ownership and voice capture lifecycle.
- Watch scheme and its host: `build-8efe40129c7d4704af1b9b53d0c32d3f.xcresult`, succeeded with zero warnings/errors.
- The preserved preferences fixture was copied to a disposable directory and reopened successfully by the new module, verifying the archived main store does not depend on an omitted WAL. Receipt: `.build/Results/App-Consolidation-Preference-Fixture-20261022.log`.

The first iOS compile identified the Watch delegate's implicit `Error` existential. Correcting it to `(any Error)?` preserved its protocol signature. Import-order formatting was applied through Mainboard. A missing newline in the synthetic identity JSON was corrected and its checksum regenerated; typed identity comparison is unchanged.

## Normal-launch correction

A normal simulator launch after the initial successful builds exposed a real executor assertion in the Objective-C `WatchConnectionServerDelegate.session(_:activationDidCompleteWith:error:)` callback. The app's new MainActor default had unintentionally isolated the previously actor-neutral delegate. Compilation and the transferred Mac tests did not exercise this iPhone runtime callback.

Both connectivity delegate classes and their request/response packet types now explicitly declare `nonisolated`. Their immutable Sendable callbacks retain the existing explicit MainActor hops; no unsafe actor assumption or suppressed concurrency warning was added. Speech event/error value types also explicitly preserve their former actor-neutral isolation. The other app Objective-C UI delegate is the Japanese UITextField coordinator, which correctly remains MainActor. URLProtocol fixtures were already explicitly nonisolated, and WatchAppDelegate remains in the separately configured Watch target.

The corrected iOS app build is `build-e71e749eb15d487f96747b27e8542e51.xcresult`, with zero warnings/errors. Normal-launch verification is performed separately by the parent task. Final post-correction Mac/Watch/lint receipts follow below.

Final post-correction results:

- Mac transferred suites: `test-c46553085a7743c3b01453c4490b6914.xcresult`, all 126 functions / 163 executions passed without failures, skips or runtime warnings.
- Watch and phone host build: `build-29d3fa2d45014e61908369fb360cca13.xcresult`, zero warnings/errors.
- Parent's normal `mainboard run --locked --no-install run` verification passed after the delegate fix: `.build/Results/App-Run-DelegateFixed-20261022.log`. The normal Home/sign-in screen rendered, and the process remained alive 28 seconds after launch. This verifies unauthenticated launch, not signed account sync or physical Watch microphone behavior.
- The frozen main-store schema checksum remains `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4`.
- Final Mainboard lint: 442 files checked, zero rewrites or failures; `.build/Results/App-Consolidation-Lint-Verified-20261022.log`.
