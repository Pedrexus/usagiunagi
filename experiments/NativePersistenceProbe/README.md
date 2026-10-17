# Native persistence feasibility check

This small, standalone macOS 27 executable tests the Apple SwiftData primitives needed to replace the legacy persistence code. It is not linked into either app and performs no network requests. Remove it when the production repository has equivalent regression tests.

Run the two commands in separate processes, with the same disposable store path:

```sh
swift run --package-path experiments/NativePersistenceProbe NativePersistenceProbe write /tmp/usagiunagi-probe.store
swift run --skip-build --package-path experiments/NativePersistenceProbe NativePersistenceProbe read /tmp/usagiunagi-probe.store
```

The first process checks an atomic answer/session save, revision-conditional acknowledgement, separate account records, and rollback after an injected failure. It saves an attempted upload marker. The second verifies that the answers, session and marker survive process exit and reopening. The prototype uses synthetic data and disables CloudKit explicitly.

Both phases passed on the installed Xcode 27.0 / Swift 6.4 toolchain on 2026-10-17. This does not test legacy database import, app lifecycle, concurrency across independent containers/processes, storage exhaustion, network reconciliation, or full feature parity. An attempted flag alone is not a complete upload protocol. Production migration must preserve the existing queue and add the remaining behavior tests before switching stores.
