# P0c proposal — unapplied production migration

Canonical checkout: `/Users/pedro/Developer/Projects/apps/usagiunagi`.
Reviewable patch: [2026-10-20-p0c-proposal.patch](2026-10-20-p0c-proposal.patch), against `3babc49d77a22081f272c5e0b887c9d8a410041a`.
Patch SHA-256: `b5d5d47e685bf99aa5ea70ee8f010688b98843761cf9f4f6f625975862c1aa77` (947 lines; nine proposed files, +716/−147).

No canonical P0c source was applied. The initial source review used installed public interfaces and text comparisons. Later disposable compilation found and corrected one API naming error; its exact scope is below. No tests, app execution, simulator launch, database opening or real account was used. Earlier disposable runtime probe results do not accept this production code or close G7. This patch is a review artifact, not a build input or automatic installation step; remove it when an accepted implementation commit makes it redundant.

## Disposable compilation

The original temporary patch had SHA-256 `b73905a60c93381a3ebea7bd1ca6f7de6bf452d9dcecc026beb01f99031662be`. Its first Mac compile failed at `Darwin.flock`: Swift selected the C structure rather than the two-argument function. This revision changes only that expression to unqualified `flock(opened, LOCK_EX | LOCK_NB)`. The installed SDK declares the public function in `sys/fcntl.h:635`; the revised expression compiles on both destinations without a C shim, private API or warning suppression.

A disposable copy of current `Shared` plus the eight shared-file patch hunks was built with Xcode 27/Swift 6.4 through Mainboard `ce36695787001398c206b5f7e0250447e3d13ee7`. The application-owner hunk was not included in that first copy; the later full-app builds below cover it. Package tests were copied to satisfy the existing manifest, but neither compiled nor run. No dependency or manifest change was needed.

| Destination | Compile-only invocation/result | Limits |
| --- | --- | --- |
| Native Mac | `mainboard run --as-is env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --package-path /private/tmp/usagi-p0c-compile-20261020/Shared --scratch-path /private/tmp/usagi-p0c-compile-20261020/build-mac --target StudyPersistence --jobs 4`; exit 0, no compiler error/warning diagnostics | Revised incremental build after the initial failure; production package only |
| Generic iOS Simulator | `mainboard apple execute` on the disposable package, scheme `StudyPersistence`, action `build`, Debug, signing disabled; exit 0; result `build-f0d4697029ec414aac215bb6474219ca.xcresult`; summary zero errors/warnings | Fresh derived-data folder; no simulator boot or application integration |

Mainboard's automatically retained iOS `.build.json` report SHA-256 is `59d1be3c6b79a6c2d8354f9f7c2b440191e8847c87cdbda19defc845b25b7dca`. The revised Mac compile log SHA-256 is `b47ac8d084f0021cd28e3d8023da3391aa01c6d88b058dbf2517a24980b04f7e`. Both live under `/private/tmp/usagi-p0c-compile-20261020`; ignored report copies are retained under the app's `.build/Reports`. These are compiler evidence, not store-compatibility or runtime receipts. The revised generation file SHA-256 is `27aef2288583cd8abbfb5becc51a7354ad444b0a1c67e2de39f5e9452e5195db`. Forward applicability was checked against current canonical files, and reverse applicability against the compiled disposable shared sources.

## Full-app compilation

A second disposable copy contains the 479 tracked files under `App`, `Shared` and `Resources` from the `517bea3e` worktree, including the three untouched off-target owner edits. It contains no Git metadata, user store, credentials, prior build outputs or symlinks. The source archive SHA-256 is `366026d372d22f86567076128d03e15dbcc81569e7540af8257a03d05f93f6f6`. The exact nine-file proposal above was applied only inside `/private/tmp/usagi-p0c-app-compile-20261020`. Reverse applicability and the owner/generation/package-pin hashes were checked again after both builds. The patch itself is unchanged.

Both Mainboard invocations used `run --as-is env -u PROTOC_PATH DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mainboard apple execute` with the disposable `App/UsagiUnagi.xcworkspace`, `--action build`, Debug, `CODE_SIGNING_ALLOWED=NO`, invocation-scoped `-skipPackagePluginValidation` and a 900-second timeout. Separate fresh derived-data folders were used for Mac/iOS. The Mac invocation also sets `CODE_SIGN_IDENTITY=-`. The sole remote pin remains official SwiftProtobuf 1.39.0, revision `3d537cb81aef272a03cb3be815439e9bf0eb3bd3`; the declared source-built generator runs, but the app does not. No global trust, signing or toolchain configuration changed.

| Destination/scheme | Result bundle | Native result summary |
| --- | --- | --- |
| `platform=macOS`, `UsagiUnagi` | `build-928467fee2f646b7ad03fda3116cccef.xcresult` | Exit 0, zero errors/warnings; arm64 Mac app including the AppKit owner check |
| `generic/platform=iOS Simulator`, `Tsurukame` | `build-a72513ef71af43088d33b2fabc6ae03d.xcresult` | Exit 0, zero errors, one known empty WatchKit-host storyboard deprecation warning; app startup compiles for arm64/x86_64 with the embedded watch/widget graph |

Both logs additionally contain Xcode's metadata-extraction-skipped message because no AppIntents framework dependency is present. This message is outside the native summary's warning count; do not describe either log as warning-free. The existing watch lifecycle/container migration remains open. No tests, simulator boot, installation, app execution, database opening or migration behavior occurred.

The original result bundles and automatically retained reports live in the disposable `Results` directory. Ignored copies of both reports are retained in the app's `.build/Reports/P0cProposalAppMacBuild.json` and `P0cProposalAppIOSBuild.json`:

| Evidence | SHA-256 |
| --- | --- |
| Mac build report | `6198862e1657cbb5ea1d7ff82f95e6812c55d4ded163b7f5f536ab51ce5ebdfb` |
| iOS build report | `e40b5e240dc6600b5075a9dbf0c7fd2b4978fe8c5f151303601f91c481a52b17` |
| Proposed `StudyApplicationOwner.swift` | `45cb8753ef1d79e2fb5c7e4be7a4c818d42db9a4633d69cfdb7fbfd709cc0c78` |
| Proposed `StudyStoreGeneration.swift` | `27aef2288583cd8abbfb5becc51a7354ad444b0a1c67e2de39f5e9452e5195db` |
| Workspace `Package.resolved` | `a44a404aa92b7f6ac990e3e55f8ac198fd0f027aeb97c5c31ddfeaf09f9ed009` |

Compilation now covers all proposed production integration, but establishes no runtime recovery, decoder compatibility or data-preservation acceptance. Explicit approval to apply the proposal is still pending. The implementation-first sequence places original-app usability comparison and final tests after the remaining production changes; it does not authorize treating these builds as G7 acceptance.

## Entrypoints and ordering

The original review-map line references below name the prospective destination files: `usagi-p0c-source/` means `Shared/Sources/StudyPersistence/`. The host row refers to the prospective `App/Application/StudyApplicationOwner.swift`. Use the exact patch for review; temporary full-file copies are not authoritative and must not overwrite current files.

| Entry | Source | Contract visible in source |
| --- | --- | --- |
| Frozen declarations | `usagi-p0c-source/StudySchemaV1.swift:8` | Top-level nominal model identities retained; V1 version 1.0.0; exactly the existing ten declarations. Empty migration plan at line 21. |
| Explicit isolated stores | `usagi-p0c-source/StudyStore.swift:57` | Existing public `open(at:inMemory:)` remains unversioned for explicit import/test stores. It reuses the same frozen models list. |
| Application startup | `usagi-p0c-source/StudyStoreGeneration.swift:38` | Acquires the root lease before preparation; retains the same lease on the exact validated candidate actor returned to the application. |
| Lifetime lease | `usagi-p0c-source/StudyStoreGeneration.swift:22` | Nonblocking exclusive `flock`, no-follow lock file, descriptor retained until actor-owned lease releases. Protects cooperating new owners only. |
| Selector resolution | `usagi-p0c-source/StudyStoreGeneration.swift:98` | Selected image is reopened; incomplete preparation retries with a fresh candidate/work UUID. Missing selector plus existing generations refuses fresh install. |
| Capture | `usagi-p0c-source/StudyStoreGeneration.swift:157` | Hashes original family, copies to temporary capture, rechecks both copies/source, synchronizes, makes retained image read-only, then renames into retained generation. Original and retained never go to persistence APIs. |
| Physical model adoption gate | `usagi-p0c-source/StudyStoreGeneration.swift:180` | Mutable verification clone metadata is read at line 184 before its first SwiftData container. A separate fresh frozen-V1 reference at lines 185–189 provides actual physical model hashes. Exact equality at line 190 is mandatory. |
| Physical metadata loader | `usagi-p0c-source/StudyStoreGeneration.swift:248` | Public `metadataForPersistentStore(type:.sqlite,at:options:)`; requires recorded SQLite type, nonempty `[String:Data]` model-version hashes, nonempty entity names/hashes. No private model inspection. |
| Verification read | `usagi-p0c-source/StudyStoreGeneration.swift:191` | Only after physical match, unversioned frozen schema reads full values from verification clone with allowsSave false. Physical metadata checked again at line 198. |
| Mutable copier source | `usagi-p0c-source/StudyStoreGeneration.swift:201` | Separate staging clone; exact preparation marker checked before public Core Data `replacePersistentStore`. No persistent API receives original/retained path. |
| Candidate validation | `usagi-p0c-source/StudyStoreGeneration.swift:215` | Exact physical hash dictionary checked before candidate's named-V1 opening, checked again after it, plus complete values, original bytes and retained bytes. |
| Complete value projection | `usagi-p0c-source/StudyStore+GenerationSnapshot.swift:36` | All ten models, all accounts/credential slots, unbound/global receipts, private handoff/binding fields, outbox attempts/issues/revisions/baselines, sessions/cursors/archive. No diagnostics redaction. No plaintext projection file. |
| Activation | `usagi-p0c-source/StudyStoreGeneration.swift:235` | Validated candidate files synchronized before atomic selected selector publication at line 240. Same live candidate actor returned; no assumed SwiftData close or iOS Process fallback. |
| Selector validation/publication | `usagi-p0c-source/StudyStoreGeneration.swift:273` / `:294` | Version/schema/phase/UUID/fingerprint shape checked, unknown top-level keys rejected; atomic plist write then file/directory synchronize. Errors preserve generations. |
| Host integration | `usagi-p0c-owner-persistence.swift:91` | Known running Mac owner check, then openApplication at line 102, then existing legacy bootstrap at line 105. Feature assembly/sync workers created only afterward. Current voice/background/mistakeSync edits preserved. |

## Physical metadata scope

The source evidence now comes from recorded persistent-store metadata on a mutable clone, not from `ModelContainer.schema` requested by this binary. `PhysicalSchema` equality compares SQLite store type and every `NSStoreModelVersionHashesKey` dictionary key/value against a fresh disposable named V1 store. Dictionary keys are the physical entity identities; differing or additional/missing entities fail equality. UUIDs and model-version identifier labels intentionally are not equated: the copy retains an existing store UUID, and this is adoption from an unnamed schema into a named but physically unchanged V1.

The public metadata loader is used only for mutable verification, reference and candidate images. Read-only Core Data metadata access may still create/change SQLite auxiliary files, hence it never receives an original or retained URL. The fresh reference uses a unique preparation path; no assumption about deterministic container deallocation/close is made.

Installed public evidence:

- macOS 27 SDK `CoreData.swiftmodule/arm64e-apple-macos.swiftinterface:103` has `metadataForPersistentStore(type:at:options:) throws -> [String:Any]`.
- `CoreData.framework/Headers/NSPersistentStoreCoordinator.h:99` defines `NSStoreModelVersionHashesKey` as the model hash dictionary used to create the persistent store. Header line 278 only guarantees type/UUID presence, so missing model hashes are an explicit refusal.
- Official API: https://developer.apple.com/documentation/coredata/nspersistentstorecoordinator/metadataforpersistentstore(type:at:options:)
- Official metadata key: https://developer.apple.com/documentation/coredata/nsstoremodelversionhasheskey

## Model and concurrent-edit preservation

The complete bodies of all ten original top-level `@Model` declarations were extracted in declaration order and compared byte-for-byte with the staged V1 declarations. Both extracted files have SHA-256 `2678c9544f161cd4d9b98b7b10715b0ca2c3bf4a3bd03576fff29b619cb63b2c`:

- `/private/tmp/usagi-p0c-original-models.swift`
- `/private/tmp/usagi-p0c-staged-models.swift`

This proves source-body equality only, not generated physical-model compatibility. The physical metadata gate must still be exercised at the final testing stage with pinned stores and all supported platforms.

The patch removes model declarations with narrow hunks. `StudyStore+Upload.swift` was refreshed from canonical after P2 verified-profile changes; its only hunk removes `UploadPauseRecord`, preserving all concurrent methods. The owner patch was likewise refreshed and adds only AppKit import, known-owner check and new opener. It preserves the now-canonical voice environment line, async background-task APIs and mistakeSync start/wake/notice changes. The former voice-only patch is historical and no longer applies; the voice line is already in canonical source. Never publish the stale full `usagi-p0c-source/StudyStore+Upload.swift`.

## Concrete old-owner evidence and exclusion limit

Repository history shows:

- `0898bfbd` introduced native Mac target bundle ID `com.pedrexus.tsurukame.mac` and `TsurukameNative/snapshot-v1.json`.
- `9d81afa9:native/TsurukameMacApp.swift:26–31` used `URL.applicationSupportDirectory/TsurukameNative/study.store` through `StudyStore.open`.
- `625447c4^:native/TsurukameMacApp.swift:62–67` still used that same root/store; its Mac project Debug and Release bundle IDs remained `com.pedrexus.tsurukame.mac`.
- The unified Mac target retains that same bundle ID and root. Current and prior native Mac entitlements show microphone access and no app sandbox/application-group shared store.

The owner therefore refuses another currently running process with that concrete bundle ID or the current bundle ID. It does not enumerate unrelated app/test/watch IDs as alleged store owners. This is a running-app snapshot, not a fence against later starts, renamed/re-signed copies, probes with arbitrary paths, or arbitrary external filesystem writers. Older binaries do not honor the new lease. A source hash before/after cannot prove an arbitrary concurrent database writer was absent. Coherent capture depends on the concrete app-private single-owner precondition; do not describe it as a generic live-store snapshot guarantee.

## Remaining limitations / final acceptance gates

1. Shared-module and full-app compilation succeed on Mac/iOS Simulator, but all migration behavior remains unexecuted. Reference creation, WAL metadata visibility, exact physical hashes and fresh-version naming need Mac/iOS/iPad acceptance against the pinned unversioned store before any data/schema upgrade is accepted. Missing/incompatible metadata must fail without selecting a replacement.
2. Historical Codable nominal types/decoders remain in current StudyCore/StudyPersistence. V1 comments explicitly forbid future decoder changes without preserving historical compatibility. Exact physical model hashes do not establish nested payload compatibility or guarantee unknown-field preservation. No V2/property normalization has been implemented.
3. No externalStorage/relationships supported; additional family files or model relationships refuse. Future external-data models require a separate complete-image preservation proof.
4. File/directory synchronization is visible in source but untested on iOS file protection, cancellation, disk-full, interruption and restart. No power-loss durability guarantee follows from source review. Candidate already validates/synchronizes before publication; a later publication-sync error may leave a fully validated selected selector visible even though startup reports failure. Interruption tests must cover that boundary.
5. Full snapshot checks requested model attributes/uniqueness/indices/relationships and all current stored field values; physical metadata now independently gates source adoption. Codable decoding faults can still be framework failures outside ordinary Swift error handling. Malformed source/payload refusal remains a final test requirement.
6. Selected ordinary-launch failures preserve paths and do not silently revert/reset. The stored validation digest describes activation-time state and is not compared to a mutable selected store on every launch. Actor/container lifetime on retry needs final verification; no public close is assumed.
7. Initial root layout is allowlisted, but later original fingerprint calls ignore non-family root siblings. A newly appearing unsupported sibling during capture is not independently revalidated. This does not establish safety against arbitrary external writers; retain the explicit single-owner limitation and test refusal boundaries before broadening supported layouts.
8. No pruning/deletion of retained, failed preparation or candidate paths exists in this foundation. Recovery UI reports failure and preserves data; cleanup is a later independently reviewed protocol.

Automatic approval review rejected the prior broad canonical publish as an untested mutation of production persistence/application files. Explicit owner approval remains pending. Archiving this revised proposal and compiling its disposable shared copy do not authorize production application. No retry or partial canonical production publish was attempted.
