# Native persistence restart check

This standalone macOS 27 executable now exercises the **production StudyPersistence store**, rather than a duplicate experimental model. It is not linked into either app and performs no external network requests. Synthetic data is written to a disposable store.

Run the two commands as separate processes, using the same fresh path:

```sh
probe_dir=$(mktemp -d)
swift run --package-path experiments/NativePersistenceProbe NativePersistenceProbe write "$probe_dir/study.store"
swift run --skip-build --package-path experiments/NativePersistenceProbe NativePersistenceProbe read-attempts "$probe_dir/study.store"
```

The first process saves account snapshots, a completed session and pending review, and separate accounts’ pending notes. It then runs the production upload lane with a synthetic timeout to persist an uncertain review and the exact attempted note revision/content. The second process verifies those values survive exit/reopening, including isolation of the other account’s notes. The simpler `read` mode checks baseline session/note preservation when upgrading a store created by an earlier probe binary. The broader StudyPersistence test suite covers atomic transactions, rollback, stale scene revisions, delayed acknowledgements, practice isolation, legacy Mac-cache import and note/download conflicts.

This does not establish the iOS SQLite import/cutover, real WaniKani uploads, physical-device behavior or full app parity. The native upload lane retains uncertain attempts; explicit user-visible reconciliation and application caller integration remain required. CloudKit is disabled for this local store.
