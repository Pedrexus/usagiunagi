# Private iCloud display preferences

The first private database syncs only appearance, Japanese review font size and the SRS indicator. It uses Apple's managed SwiftData/CloudKit transport and an independent, one-model schema. It adds no CloudKit network client, synchronization engine or package dependency.

## Authority and isolation

### Expanded settings scope requested by the owner

The initial three-field implementation below is a foundation, not completion of the expanded request to share app-owned settings across all devices. The official [WaniKani User API](https://docs.api.wanikani.com/20170710/#user) was checked October 21, 2026. Its six editable preferences are `extra_study_autoplay_audio`, `lessons_autoplay_audio`, `lessons_batch_size`, `reviews_autoplay_audio`, `reviews_display_srs_indicator` and `reviews_presentation_order`. `default_voice_actor_id` is a fixed deprecated value; `lessons_presentation_order` is also deprecated and ignores updates. Do not treat either as a working user control.

The implementation sequence for the expanded request is:

1. Read those supported preferences from the verified WaniKani account. Keep an account-fenced offline cache; never infer ownership from a reused username. Explicit account changes clear the old live projection. Any new persistent value must respect the existing historical-decoder/migration gate rather than extending the frozen study profile casually.
2. Map actual behavior before choosing an equivalent app control. In particular, WaniKani's SRS field controls the indicator after a completed answer; this app's name/dots stage style is a distinct presentation preference. Keep lesson/review/Extra Study audio independent. Ignore deprecated API fields as authorities for custom app features.
3. Keep WaniKani-supported settings under that API authority. Explicit changes can use `PUT /user` when the token permits them; read-only/denied updates retain the server value with a useful inline message. Do not send a preference PUT from iCloud reconciliation, startup defaults or an exercise-upload retry. Do not silently apply preference changes to an already captured review session's grading options.
4. Extend the private store's allowlist to app-specific review/lesson policies, subject presentation, appearance, font/voice selections and other portable preferences. Global display choices and account-specific learning choices need distinct scopes. Exclude tokens, developer endpoints, progress/outboxes, device permission grants, downloaded files and filesystem paths. Share a portable selection or intent rather than another device's local resource location.
5. Preserve locally edited app preferences and use WaniKani as the baseline for fields it owns. Any deliberate app override must have explicit provenance; a full dictionary merge or last-arriving snapshot cannot decide ownership safely. Retain existing recent-mistake parity and its account fences while deciding whether that app-only history needs a stronger private transport.

Source implementation of those additional mappings and fields remains open. The initial private database does not yet fetch, update or cache WaniKani preferences, nor does it sync all other app settings. The owner subsequently requested tests only after all changes and permitted manual checks; earlier passing receipts retain their earlier scope, and no further test run should be scheduled during implementation.

| Data | Authority and transport |
| --- | --- |
| Subjects, assignments, SRS stages and accepted answers | WaniKani; the existing API refresh and reconciliation |
| Pending answers, active sessions, attempts and uncertainty | The existing local `StudyStore` and protected WaniKani outbox |
| Notes and synonyms | Existing WaniKani material reconciliation; excluded from this private database |
| API tokens and account identity | Existing Keychain/account owners; excluded from this private database |
| Appearance, Japanese font size, SRS indicator | Local preferences plus the independent private CloudKit display store |
| Other preferences, downloaded fonts/media and device permissions | Existing local owners; excluded from this first cloud scope |
| Recent-mistake practice hints | The existing account-fenced iCloud key-value bridge; unchanged |

`StudyStore` and every generation-opening configuration retain explicit `cloudKitDatabase: .none`. Enabling the app's CloudKit entitlement cannot opt that store into mirroring. The new store is a sibling at `Application Support/UsagiPrivatePreferences/preferences.store`, outside the study-generation directory. Its `PrivatePreferencesV1` schema contains only `Change`; the canonical study schema, historical writer and frozen fixtures are untouched.

Display preferences apply across WaniKani accounts using the same app installation/iCloud account. The private records contain no WaniKani identity. A downloaded display edit cannot call the WaniKani client, modify study records or enqueue an answer. The allowlist is implemented in one concrete owner, rather than serializing the full ReviewPreferences value into CloudKit.

## Edits and conflicts

Only an explicit change to one of the three supported fields publishes an edit. Starting the app or opening a new device does not publish its defaults. Previously saved local display choices stay local until edited; they cannot silently replace a device's cloud history on first launch.

Each edit creates a new immutable row with a field name, scalar value, logical revision, random UUID and format version. There are no uniqueness constraints or relationships. Existing rows are never rewritten or deleted by this client. SwiftData manages CloudKit delivery; the app folds edits independently per field. The greatest logical revision wins, with UUID and value ordering resolving ties deterministically. This is a convergence rule for concurrent/offline display choices, not a global wall-clock claim. Disconnected devices may choose different values temporarily, and an edit made without seeing another device's higher revision can lose when they reconnect. Editing after that reconciliation advances the known version.

Different fields therefore do not replace one another through a whole-settings snapshot. Reconciliation updates only the three corresponding fields of the existing AppStorage preferences, preserving review policy, grading, audio and session options. Reapplying the same data writes nothing and does not echo an imported change into another cloud record.

Unrecognized fields remain unapplied. Unsupported versions, invalid revisions and invalid values preserve their source rows; known fields using a future format block this client's writes. Font sizes must match the existing 100–250% picker in 25% steps. Logical counter overflow refuses publication. Malformed local preferences are not reset by a cloud read.

An explicit edit is also marked in a small, field-specific local defaults entry until it commits to the sidecar. If that save fails or the sidecar is unavailable, reconciliation cannot overwrite the pending local field. A subsequent store opening retries that edit once. This is separate from, and cannot affect, WaniKani's review outbox. A crash between commit and clearing the marker may replay the same display choice as another edit; it cannot duplicate an exercise submission. There is no timer, forced CloudKit upload or acknowledgement claim.

## Configuration and activation

`USAGI_ICLOUD_CONTAINER_IDENTIFIER` defaults to `iCloud.com.pedrexus.usagiunagi` in both Xcode configurations. It feeds the iPhone/iPad and Mac CloudKit entitlements and the `UsagiPrivateCloudContainer` Info.plist entry. This is a requested identifier, not evidence of a registered or accessible container. The project declares iCloud/Push capabilities and iOS remote-notification background mode. Source push entitlements target development; distribution signing and production schema promotion are separate release work.

Before constructing the private store, the owner asks SwiftData to discover the signed app's configured container and requires an exact match with the requested identifier. Unentitled or mismatched builds use the same isolated schema locally, without constructing a CKContainer or opening a private cloud database. Store-opening errors leave the study app and local settings usable. The Settings row describes configuration, not confirmed delivery to another device.

Live activation still requires the owner's Apple Developer team to register/associate that shared container with both app identifiers and create valid signing profiles. The checked-in iOS signing identity remains upstream's; this fork cannot assume ownership of upstream iCloud, App Groups or Keychain. No team, bundle identity, sandbox boundary or credential namespace is changed here. Once the owner selects those identities, verify the signed entitlements on both products, initialize and inspect the development schema, and test two disposable accounts/devices before any production promotion.

Do not initialize or promote a CloudKit schema during ordinary app launch. The first signed acceptance must cover offline disjoint/same-field changes, relaunch, iCloud unavailability/quota/account changes, background import and an unchanged WaniKani outbox. Existing simulator/local tests cannot establish those delivery outcomes.

## References and evidence

Apple documents the [managed SwiftData sync requirements and CloudKit schema limits](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), including explicit `.none` for stores that must not mirror. Its [private database configuration](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct/private(_:)) identifies a particular container. Both references were retrieved October 21, 2026 and checked against the installed Swift 6.4/Xcode 27 interface.

Local test and build receipts are recorded in the [implementation checkpoint](Implementation/2026-10-21-frozen-ios-and-review-focus.md#private-icloud-display-preferences). Private CloudKit delivery, container registration, signed entitlement inspection and rendered settings acceptance remain open; no real iCloud account has been accessed.
