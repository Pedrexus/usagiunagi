# Native persistence restart check

This standalone macOS 27 executable now exercises the **production StudyPersistence store**, rather than a duplicate experimental model. It is not linked into either app and performs no network requests. Synthetic data is written to a disposable store.

Run the two commands as separate processes, using the same fresh path:

```sh
probe_dir=$(mktemp -d)
swift run --package-path experiments/NativePersistenceProbe NativePersistenceProbe write "$probe_dir/study.store"
swift run --skip-build --package-path experiments/NativePersistenceProbe NativePersistenceProbe read "$probe_dir/study.store"
```

The first process saves account snapshots, a completed session and pending review, its attempted-upload marker, and separate accounts' pending notes. The second verifies the production Codable models survive process exit/reopening with those values intact. The broader StudyPersistence test suite covers atomic transactions, rollback, stale scene revisions, delayed acknowledgements, practice isolation, legacy Mac-cache import and note/download conflicts.

This does not establish the iOS SQLite import/cutover, real WaniKani uploads, physical-device behavior or full app parity. An attempted flag must still be connected to explicit reconciliation before review upload integration. CloudKit is disabled for this local store.
