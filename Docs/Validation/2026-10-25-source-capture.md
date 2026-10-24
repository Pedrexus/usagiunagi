# Cross-volume source-capture recovery

October 25, 2026; production opener at app commit `a3c02c52`. No app source,
schema, frozen fixture or production fault hook changed.

Both a base frozen store and a store with committed WAL data encountered an actual
copy failure at `preparations/<candidate>/capture/study.store`: Cocoa 640 with
underlying POSIX 28 (ENOSPC). The existing inspection probe caught the error and
exited 74 without a signal. After space was released, two fresh processes per
variant restored all 38 expected records and selected a fresh candidate.

The disposable source stayed on the host APFS volume; `preparations` mounted a
separate bounded 128 MB APFS image, preventing same-volume clone optimization.
Reported capacity was 127,959,040 bytes. A pressure file occupied 123,531,264 bytes;
deleting a preallocated 131,072-byte reserve allowed preparation metadata but not
the source copy. Only this disposable image was filled.

The starting selector was a seeded valid preparing state from an earlier interrupted
fixture, with fresh candidate/retained identities and exact source hashes. This
checks recovery from that state, not initial selector publication. The WAL variant
used the existing native WAL seed command (expected exit 86), retained the original
database hash and supplied updated expected records before invoking the opener.

Both original/retained sources and failed preparation file hashes stayed unchanged
through recovery. The failed capture file was empty. The WAL variant additionally
checked all database/WAL/SHM hashes and failed preparation path membership. Both
images were ejected and removed after successful checks.

This proves Mac cross-volume copy-failure recovery. It does **not** prove failure
during same-volume APFS cloning, interruption after nonzero copied bytes, interruption
inside selector publication, iOS behavior or physical-device behavior. Those gates
remain open; physical-device checks are owner-deferred.

Local evidence is retained under `.build/Results/`:

| Directory | Driver SHA-256 | Receipt SHA-256 |
| --- | --- | --- |
| `CrossVolumeCapture-20261025` | `a60138a5da129f6da00fd517ca2b82c124fce6608071511b9ec78ec3629abed2` | `0ad9a448d229f3d9d0280decf5957e1fdc8fceb125964f486049d7e89c859561` |
| `CrossVolumeCapture-20261025-WAL` | `8ef35d14c1ab5037ff740d59fbfdfc2abb03815300ffa88892ba297a72424202` | `e275900c88066ab17269fd391c5b425aa3127a8476ecbf7d6a4d2c4728908d8d` |

Each directory contains the exact temporary driver, capacity/candidate/hash receipt,
capture error, two reopen logs and detach evidence. Execution used the committed
Mainboard `7dfce9f` snapshot with a 240-second outer limit and bounded subprocesses.
No one-off experimental tool was added to the app or its permanent suite.

## Interruption inside final selector publication

A separate bounded debugger experiment now covers a Mac process interruption inside
`StudyStoreGeneration.publish`, after the atomic selector write and permissions update,
but before `synchronizeFile(selectionURL)` at line 415. LLDB resolved one source
breakpoint, ignored the first two preparing publications, and stopped on its third hit.
The stopped frame and selected selector were inspected before `process kill` reported
exit status 9. This changes no production source and adds no app fault hook.

Both journal-free and committed-WAL disposable sources passed. Two fresh processes
restored the exact 38-record state with unchanged selection and source/retained hashes.
The existing first-write command then committed an answer/outbox and note and exited
86 deliberately. Two more fresh processes restored all 39 expected records. All source
DB/WAL/SHM files, retained files and the frozen fixture remained unchanged throughout.

The first WAL driver expected zero from the deliberate-exit first-write command and
stopped after its successful save. The recovery driver explicitly accounts for exit 86
and continued that same fixture, without repeating the mutation. Both the initial
failure and continuation receipts are retained; this was a harness expectation error.

Evidence: `.build/Results/PublicationDebugger-20261025` and
`PublicationDebugger-20261025-WAL`, each containing the exact driver, debugger transcript,
initial reopen logs, first-write log, two written-state reopen logs and
`post-write-receipt.json`. `Publication-Debugger-Postwrite-20261025.log` reports both passes.
The probe binary SHA-256 is
`fea66c09d7332b287cb9302c2e3e9d7c319c908802b662a3cca6d1e8b01704ca`.
The opener is unchanged from `a3c02c52`, SHA-256
`8d0f4da0b3937c0ec5d75e2c0bbf3a8dbb554f1ef96cfaa957b33681b5d26b33`.

This closes the tested Mac pre-fsync process-interruption point. It does not establish
power-loss durability, every instruction within atomic replacement/fsync, iOS publication
interruption, or nonzero mid-copy interruption. The cross-volume capture results above
retain their original scope.
