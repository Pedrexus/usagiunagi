# Native store generation opening

The owner explicitly approved applying the reviewed proposal on October 20, 2026. Production startup uses `StudyStore.openApplication(in:)`. The original implementation checkpoint below was compiler-only; the deferred test stage now includes the scoped, separate-process Mac evidence below. G7 remains open. No real account or production store was opened.

## Production opener: separate-process Mac checks

The existing DEBUG persistence probe now calls the actual application opener against disposable copies of the frozen `native-v0-186c1cc3` store. Its first run exposed a real publication defect: `capture` was made read-only before `FileManager.moveItem` published it as the retained generation. macOS refused that move with Cocoa error 513/POSIX 13 (probe exit 251). Publication now moves the coherent capture first, then applies read-only protection. Protection is reapplied on retry when the retained directory already exists. The original database family and model/encoded payload declarations are unchanged.

After the fix, `probe-application-opening` exits 0 and verifies:

- Both the frozen base and a separately stopped WAL-only writer preserve all 38 exact records across ten model types/two accounts when adopted and reopened in fresh processes.
- A second process is refused while the returned application actor owns its lease.
- An answer and note saved through the selected store survive `_exit(86)` and two fresh process reopens, with 39 exact records. Original/retained database-family bytes and the selection receipt remain unchanged by those writes.
- A fresh installation selects one empty named generation, reopens it twice and refuses a second owner. Frozen fixture filenames and SHA-256 values remain unchanged.

The corrected binary also opens the actual disposable preparation left by the initial failed run, preserving all 38 records. Logs are `.build/Results/ApplicationOpeningProbe.log` and `ApplicationOpeningInterruptedRetry.log`. The successful disposable root is `native-upgrade-6C5C4F95-00D8-4719-9E5D-E0D513EAFBDB` under the system temporary directory; the earlier interrupted root ends in `BA06423C-5DA8-4051-819C-6FEB791BC6F9`. The first failure was observed in command output; no separate frozen failure log is claimed. The workflow runs this existing probe command after the schema-copy experiment.

These are Mac process/restart checks of the production opener, not a V2 migration, mid-copy kill, disk-full, file-protection, power-loss or frozen-store iOS/iPad result. The remaining failure and compatibility gates below still apply. Shared `StudyStoreOpeningTests` add malformed/foreign/empty/sidecar and rollback-image cases. They pass in the iPhone shared suite and in the final focused Mac rerun; the never-opened-copy setup and canonical path-key fixes, their failures and exact scope are recorded in the [test checkpoint](2026-10-20-original-flow.md#native-navigation-and-final-test-ports).

## Implementation and ownership

- `StudySchemaV1.swift` preserves all ten original top-level model identities and declaration bodies, names V1 as 1.0.0, and supplies an empty migration plan. There is no V2 or property normalization. Existing `open(at:inMemory:)` remains available for explicit isolated import/test stores.
- Application opening acquires a nonblocking no-follow file lease, retained by the returned actor for its lifetime. The Mac owner first refuses another running app with the current or historical `com.pedrexus.tsurukame.mac` identifier. Feature and sync workers are assembled only after opening and legacy bootstrap finish.
- A strict binary property-list selector records preparation/selection, schema version, generated UUID paths and source fingerprints. Missing selection beside existing generations refuses a fresh install. Interrupted preparation uses fresh candidate/work paths; failed or retained paths are never automatically deleted or selected as fallback.
- Original database/WAL/SHM bytes are copied and fingerprinted before/after capture; the retained image becomes read-only. Persistence APIs receive separate mutable verification, reference, staging or candidate paths, never the original or retained image.
- Public Core Data metadata must show SQLite and exactly the fresh named V1 reference's nonempty entity-hash dictionary before a verification clone opens in SwiftData. The public store copier creates the candidate from separate staging. Physical metadata and complete domain values are checked again before activation.
- A complete actor-owned snapshot includes all accounts, credential slots, global/unbound receipts, private handoff/binding state, session state, outbox revisions/attempts/issues/baselines, cursors and archives. Candidate files are synchronized before atomic selector publication. The exact live candidate actor is returned; no assumed SwiftData close or iOS process fallback is used.

## Source-review correction

The approved patch used sorted-key JSON bytes to compare every field. Review found that `StudyLegacyHandoff.preferences` contains three Sets: fonts, notifications and selected audio voices. Sorted JSON keys do not stabilize Set array encoding, so equivalent independent decodes could incorrectly reject a valid store.

`StudyGenerationSnapshot` now compares encoded non-handoff contents plus a typed `[sourceID: StudyLegacyHandoff]` map. A nil/present marker remains in every receipt's field map. Synthesized handoff/preferences equality includes all private state and compares Sets by membership; session/catalog arrays retain their original order. Duplicate record identities throw before returning. No persisted encoder, model declaration or domain payload format changed. A second source review verified this fix and found no additional confirmed defect; that is not behavioral acceptance.

The selector's activation-only fingerprint encodes the entire validated snapshot, including handoffs. Its Set ordering may vary for equivalent values. It is a receipt fingerprint, never the equivalence predicate or a checksum compared against a later mutable selected store.

## Canonical compiler and source evidence

Based on `71462b56`, with the three preexisting owner edits preserved and excluded from this change. Mainboard `ce36695787001398c206b5f7e0250447e3d13ee7`; Xcode 27, Swift 6.4. Formatting and strict SwiftLint checks pass for all nine changed production files without rewrites. Both final builds include the typed-comparison correction:

| Destination | Result bundle in `.build/Results` | Native summary |
| --- | --- | --- |
| Native Mac, scheme `UsagiUnagi`, Debug | `build-bd1525f3cb514a3286453855dc92b842.xcresult` | Exit 0, zero errors/warnings |
| Generic iOS Simulator, scheme `Tsurukame`, Debug | `build-6727c1d270cf4164b39298dbb6da401d.xcresult` | Exit 0, zero errors/warnings |

These are incremental compiler checks, not test or Release acceptance. Both logs contain Xcode's metadata-extraction-skipped message because no AppIntents dependency is present, outside the native summary's warning count. The earlier fresh iOS build's empty WatchKit-host storyboard warning remains open.

Mainboard invoked `apple execute` on the canonical workspace with separate `NativeCanonicalMac`/`NativeCanonicaliOS` derived-data folders, `--action build`, Debug, signing disabled, a 900-second timeout and invocation-scoped `-skipPackagePluginValidation`; the Mac command also sets `CODE_SIGN_IDENTITY=-`. `PROTOC_PATH` was unset. Official SwiftProtobuf remains locked to 1.39.0/revision `3d537cb81aef272a03cb3be815439e9bf0eb3bd3`. No signing, global trust, toolchain selection, dependency or network-account setting changed.

| Frozen evidence | SHA-256 |
| --- | --- |
| Mac `.build.json` report | `bcc8c30eab6125ab9241a86c9f309e265fca09bf3bcd88b83ab90a9b66cfd7d2` |
| iOS `.build.json` report | `597ab93ab8bb0e730c222a2bb41546fdfb30306e02cf24260d8883ceba8604a5` |
| `App/Application/StudyApplicationOwner.swift` | `3489b3b7da6564feaf8755548b511118c025d42a510fc036e1bcfe22354f1f77` |
| `Shared/Sources/StudyPersistence/StudySchemaV1.swift` | `538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4` |
| `Shared/Sources/StudyPersistence/StudyStore+GenerationSnapshot.swift` | `48b297abe415395f7bec8e87b3b1c65ef4b2ef468f7a5e927ac28e8a191d0e85` |
| `Shared/Sources/StudyPersistence/StudyStoreGeneration.swift` | `1d4ffaf633f9bb1547366b9bbb6af21b2fec3c748f211b5255c5d84638d8ffa6` |
| `.build/Reports/NativeStoreOpeningInventory.json` | `410b4c1e007b0208c480acfc8bf833c7d474a557046900300eec4550edfd7d7b` |
| `.build/Reports/NativeStoreOpeningSourceComparison.json` | `34528b20218090d273a9e7134b810169d977d2111a0e302a182ab3aedbb86ca8` |

Mainboard's inventory parses 266/266 Swift files with zero gaps/context issues: production 145 files/21,125 physical lines, tests 116/23,717, tooling 5/282. Production grows 638 lines versus the WidgetKit checkpoint's 20,487; this adds recovery infrastructure, not a LOC reduction. Test/tooling sizes are unchanged. Counts classify sources, including the three off-target owner files, without inferring target membership. The first inventory invocation lacked `DEVELOPER_DIR` and failed because the globally selected command-line tools lacked SwiftParser libraries; the explicit-Xcode rerun succeeded without changing global selection.

## Remaining acceptance gates

1. G7 must exercise the production opener with pinned unversioned stores and fresh installs on Mac/iOS/iPad. Prove WAL visibility, physical identity before/after named adoption, exact values, second reopen, retries and rejection of missing/incompatible metadata. Compilation proves none of these runtime behaviors.
2. Historical nested Codable types/decoders still live in current StudyCore/StudyPersistence. The frozen V1 declarations forbid changing them without compatibility proof, but their decoders are not independently frozen. Exact physical hashes do not establish nested payload or unknown-field compatibility. Complete that foundation before a V2/property migration.
3. The new lease protects cooperating new owners only. A running-Mac-app snapshot does not fence later old binaries, re-signed copies, arbitrary probes or external writers. Capture requires the documented quiescent app-private single-owner precondition; matching hashes are not a generic live-store snapshot guarantee.
4. External storage, relationships and unknown store-family files/layouts are unsupported and must refuse. Initial root siblings are allowlisted; newly appearing non-family siblings are not independently rechecked by later source fingerprinting. Do not broaden this contract without complete-image preservation evidence.
5. Exercise cancellation, file protection, disk-full, interrupted capture/copy/validation/selection, process restart and selected-open failure. Synchronization source does not prove power-loss durability. A publication-sync error may leave the already validated selection visible while startup reports failure; test that boundary. No silent downgrade/reset is permitted.
6. Prove malformed model/payload handling and retry/actor lifetime. Framework Codable failures may be fatal outside ordinary Swift errors. Preserve all paths on refusal. Retained/failed generation pruning remains a separate future protocol.
7. Add the identified regression at the final test stage: an unfinished handoff with multiple fonts, notifications and voice IDs, private active/revoked binding state, nil versus present preferences, duplicate receipt rejection and order-sensitive session/catalog changes. Check the same state after reopening.

## Historical review evidence

The initial source review, old-owner history and disposable build evidence remain in Git at `71462b56:Docs/Implementation/2026-10-20-p0c-proposal.md`. The exact approved patch is retained at `517bea3e:Docs/Implementation/2026-10-20-p0c-proposal.patch`, SHA-256 `b5d5d47e685bf99aa5ea70ee8f010688b98843761cf9f4f6f625975862c1aa77`; its redundant current-tree copy is removed now that production source is authoritative. Initial declaration-body extracts both had SHA-256 `2678c9544f161cd4d9b98b7b10715b0ca2c3bf4a3bd03576fff29b619cb63b2c`; the canonical V1 file remains byte-identical to the disposable compiled V1. This is source preservation, not physical-model acceptance. The former automatic-review blocker is resolved by the owner's explicit approval; G7 remains open.

Public metadata APIs: [metadataForPersistentStore](https://developer.apple.com/documentation/coredata/nspersistentstorecoordinator/metadataforpersistentstore(type:at:options:)), [NSStoreModelVersionHashesKey](https://developer.apple.com/documentation/coredata/nsstoremodelversionhasheskey). Installed SDK metadata documentation guarantees type/UUID, not model hashes, so missing/nonempty-hash checks are explicit refusals. Metadata inspection is restricted to mutable copies because even read-only opens may maintain auxiliary files.
