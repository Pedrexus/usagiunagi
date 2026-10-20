# Production persistence restart checks

This macOS 27 executable tests StudyPersistence using disposable stores and synthetic account data. It is not linked into the app. No mode accesses a live account, system Keychain or saved preferences.

From the monorepo root, `mainboard run --as-is usagi-test-persistence` builds with two compiler jobs and runs eight phases within a 600-second deadline: `write` → `read-attempts`, `write-catalog` → `read-catalog`, `read-native-baseline`, `probe-native-upgrade`, `probe-application-opening` and `probe-application-payload-corruption`. The original pairs use separate processes and preserve completed sessions, uncertain answers, exact attempted notes, account isolation and catalog metadata. The simpler `read` mode accepts stores from earlier probe binaries. The catalog reader also verifies that an older unbound import receipt does not select a writer.

The DEBUG-only baseline reader and upgrade experiment share the pinned fixture at `Fixtures/native-v0-186c1cc3/study.store`, written by `186c1cc3`. They validate its provenance and copy it before any persistence API opens a store. The complete baseline covers 38 records, ten model types, fifteen Codable attributes and two accounts, including global/unbound receipts. Never regenerate this fixture to make a migration pass.

`probe-native-upgrade` names the unchanged schema as version 1.0.0 and uses the public Core Data store-replacement API on disposable clones. It requires exact schema/domain equality in fresh processes, preserves a committed WAL-only material edit, and proves a named-schema save survives reopening. It also records the limits of a read-only source option: writable clones can gain/change SHM and WAL bookkeeping; a filesystem-protected journal-free source refuses with SQLite error 8, while the protected WAL generation remains byte/name-exact. Candidate permissions change only on its disposable copy. The original fixture's complete file names and SHA-256 hashes must remain unchanged.

The experiment's `verify-native-upgrade`, `seed-native-upgrade-wal` and `write-native-upgrade` child commands require its marked temporary fixture. The WAL writer deliberately exits 86 after a real committed save; the parent requires that exit and checks the saved state. The primary phase exits 0 only after its assertions pass. This is macOS 27 test evidence: its schema still references current model classes and has no migration stages. It does not implement production capture/selection, freeze a historical V1, change stored fields, prove external-data copying, run inside iOS or close G7. No production model, container or bootstrap code is changed.

The same binary has handoff checkpoints. With a **fresh** disposable path, run these in order, each through `mainboard run --as-is mainboard proc timeout 60 apps/usagiunagi/.build/Probe/debug/NativePersistenceProbe <mode> <absolute-store-path>`:

| Mode | Expected exit | Boundary |
| --- | --- | --- |
| `import-handoff` | 86 | Import and verified prepared binding committed; credential not saved |
| `save-handoff` | 86 | Synthetic credential file persisted; writer not activated |
| `activate-handoff` | 86 | Native writer choice committed; abrupt exit before first preference write |
| `edit-handoff` | 0 | Change native work, consume the old answer and simulate logout |
| `read-handoff` | 0 | Reopen offline without reading retired data or resurrecting old work |

Exit 86 is deliberate `_exit(86)`, skipping SwiftData/Swift teardown. The latter processes cannot verify identity online, so successful recovery requires the durable binding and preference snapshot. The activation phase uses a disposable defaults subclass to exit before hydration; resumed phases verify original preferences and the absence of a token preference. The workflow requires the exact checkpoint message as well as exit 86. Credentials use a separate disposable file; that exercises commit ordering, not Apple's Keychain internals. Do not run a new writer over an existing account store.

With a second fresh path, `rollback-handoff` must exit 86 after a malformed pending answer rolled back. `verify-rollback-handoff` then exits 0 only if a fresh process finds no partial catalog, account, snapshot, receipt binding, pending work or credential. The existing shared GitHub Actions job includes all phases through Mainboard. Timeouts, crashes with another exit code and unexpectedly normal exits fail the gate.

For native schema upgrades, build the writer from the exact earlier committed source in a disposable package, then run the current `read-catalog` against that store. The handoff checkpoint validates `2e77f23` → current, including the optional receipt attribute. Earlier catalog upgrades are historical evidence in Docs/Validation.

These checks do not activate the iOS writer cutover or prove physical/signed-device behavior, actual Keychain failures, power-loss durability or complete app parity. Actual SQLite schemas 9–15 and unchanged source bytes are covered separately by hosted Swift Testing. CloudKit remains disabled for this local store.

`probe-application-opening` exercises the production generation opener on marked disposable copies: base/WAL adoption, lease refusal, committed answer/note survival across abrupt exit and fresh-process reopens. `probe-application-payload-corruption` runs 27 scenarios: two truncated payloads, fifteen wrong-typed JSON fields, nine required NULL mutations and one populated review-issue control with exact 38-record comparison. Each exercised negative case must throw safely (exit 74); signals or returned owners fail. SQL constraint rejections are explicitly unexercised. Original/retained/selector bytes, generation membership and selected DB/WAL must stay unchanged; selected SHM bookkeeping may change. Children have time/output/free-space bounds, and only passed marked copies are removed after assertions. Both primary commands are in the existing Actions persistence lane; publication and a hosted run remain pending.

`probe-application-payload-validation` separately records the public Core Data binary-projection experiment. Its successful raw preflight is not a substitute for the actual production-opener command. These commands require the same pinned fixture argument as `probe-native-upgrade` and a command-scoped Xcode 27 `DEVELOPER_DIR`; run them through root Mainboard with a hard timeout. Never run child commands or SQL corruption against an unmarked store. The broader failure matrix and physical iOS adoption remain open.

The catalog reader also verifies old account bytes decode with no `catalogRefreshID`. Automatic-read acceptance builds the writer from exact commit `70414fb6` in a disposable archive, then reads that store with the current binary. The optional marker belongs to the existing Codable account value; no SwiftData column is added. See [current evidence](../../../Docs/Validation/2026-10-20-automatic-catalog-reads.json).
