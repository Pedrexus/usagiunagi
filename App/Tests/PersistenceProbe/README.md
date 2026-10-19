# Production persistence restart checks

This macOS 27 executable tests StudyPersistence using disposable stores and synthetic account data. It is not linked into the app. No mode accesses a live account, system Keychain or saved preferences.

From the monorepo root, `mainboard run usagi-test-persistence` builds it and runs the original `write` → `read-attempts` and `write-catalog` → `read-catalog` checks in separate processes. These preserve completed sessions, uncertain answers, exact attempted notes, account isolation and catalog metadata. The simpler `read` mode accepts stores from earlier probe binaries. The catalog reader also verifies that an older unbound import receipt does not select a writer.

The same binary has handoff checkpoints. With a **fresh** disposable path, run these in order, each through `mainboard run --as-is mainboard proc timeout 60 apps/usagiunagi/.build/Probe/debug/NativePersistenceProbe <mode> <absolute-store-path>`:

| Mode | Expected exit | Boundary |
| --- | --- | --- |
| `import-handoff` | 86 | Import and verified prepared binding committed; credential not saved |
| `save-handoff` | 86 | Synthetic credential file persisted; writer not activated |
| `activate-handoff` | 86 | Native writer choice committed before abrupt exit |
| `edit-handoff` | 0 | Change native work, consume the old answer and simulate logout |
| `read-handoff` | 0 | Reopen offline without reading retired data or resurrecting old work |

Exit 86 is deliberate `_exit(86)`, skipping SwiftData/Swift teardown. The latter processes cannot verify identity online, so successful recovery requires the durable binding. Credentials use a separate disposable file; that exercises commit ordering, not Apple's Keychain internals. Do not run a new writer over an existing account store.

With a second fresh path, `rollback-handoff` must exit 86 after a malformed pending answer rolled back. `verify-rollback-handoff` then exits 0 only if a fresh process finds no partial catalog, account, snapshot, receipt binding, pending work or credential. The existing shared GitHub Actions job includes all phases through Mainboard. Timeouts, crashes with another exit code and unexpectedly normal exits fail the gate.

For native schema upgrades, build the writer from the exact earlier committed source in a disposable package, then run the current `read-catalog` against that store. The handoff checkpoint validates `2e77f23` → current, including the optional receipt attribute. Earlier catalog upgrades are historical evidence in Docs/Validation.

These checks do not activate the iOS writer cutover or prove physical/signed-device behavior, actual Keychain failures, power-loss durability or complete app parity. Actual SQLite schemas 9–15 and unchanged source bytes are covered separately by hosted Swift Testing. CloudKit remains disabled for this local store.
