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

## Nonempty interruption during source-family capture

The same unchanged probe also stopped at `StudyStoreGeneration.swift:429`, immediately
after the first `FileManager.copyItem` returns and before its permissions update or the
next family member. LLDB reported one resolved location, first-hit interruption and
process kill status 9. Source and capture had the same filesystem device ID.

Both base and committed-WAL cases left exactly `capture/study.store`, 180,224 bytes,
matching the original database hash. The WAL case had not yet copied either sidecar;
the retained generation did not exist. The selector remained preparing. Two fresh
processes per case restored all 38 exact records, with a different candidate but the
same retained identity. Every abandoned preparation file, original DB/WAL/SHM file,
retained file and frozen-fixture hash remained unchanged; selection stayed stable
after the successful retry.

Receipts and exact driver: `.build/Results/CaptureDebugger-20261025` and
`CaptureDebugger-20261025-WAL`. Each contains `interruption.log`, `reopen-0.log`,
`reopen-1.log`, `receipt.json` and `driver.py`.
`Capture-Debugger-20261025.log` reports both passes. The probe binary and opener
hashes match the publication experiment above. No source, schema or fixture changed.

This closes the tested same-volume, nonempty source-family capture interruption:
one whole file copied, remaining WAL family incomplete. It does not prove interruption
inside a single `copyItem` call, failure inside APFS clone optimization, iOS capture or
physical power-loss behavior. Those narrower boundaries must not be inferred from this result.

## Interruption inside a nonempty single-file copy

At app `2d1907bb` (production opener last changed at `c2c7e62c`), a fresh probe build
now verifies a true partial-file interruption for both base and committed-WAL sources.
Only disposable copies were repaged to 65,536-byte SQLite pages using DELETE journal
mode and VACUUM, retaining the frozen logical schema/records. The resulting database
is 2,359,296 bytes. WAL seeding uses the existing probe's deliberate exit 86 and its
updated exact baseline. The original frozen fixture is unchanged, SHA-256
`f82be6077bbe12593c95c3ef27b7df576e65dde06965b0a297dbd12be3a3bf94`.

Each capture directory resides on a bounded 128 MB disposable APFS image, a different
filesystem device from the source. LLDB first stops at the production copyItem call,
then at libcopyfile's copyfile_data and its native write syscall. Stepping out of that
write returns 1,048,576 bytes while still inside copyfile_data; process kill reports
status 9. The captured file is exactly 1,048,576 bytes, smaller than the source.
No registers, app source, schema or production fault hooks were changed.

Two fresh processes per variant restore all 38 exact records. Retry selects a new
candidate, the abandoned preparation hashes stay unchanged, and original/retained
files match the source hashes (including WAL/SHM for the WAL case). Selection is
stable on the second reopen. Both images were ejected after verification.

Receipts and exact drivers: `.build/Results/MidCopy-Repaged-20261025` and
`MidCopy-Repaged-WAL-20261025`, including debugger transcripts, files.json,
receipt.json, both reopen logs and detach logs. Driver SHA-256 values:

- Base: `19c6b03eb96cdc407a9a7f7c972f23441775dac999b163229adc23c3176c5713`.
- WAL: `f42623545a6f8601d262cbe599cc16cb7f64d852f4a298976ec64301d55dd54c`.
- Probe: `f9ef686d26645657c9e448933432c4d0bcce6a9b53d8e107daaddabbb0f76e8f`.
- Opener: `669a2df30a48a57ba841c2360d52a0974e56aa0a1b0a7d15b0c3e103d8d72ecb`.

Initial discovery wrote the entire 180,224-byte fixture in one syscall, which did not
qualify as partial-copy evidence. The first repaging attempt remained in WAL mode and
failed its size precondition before creating/mounting a volume. Both receipts remain
under MidCopy-Discovery-20261025 and MidCopy-Partial-20261025; neither is counted as
a recovery pass. Correcting the disposable repaging setup produced the results above.

This closes this Mac cross-volume nonempty single-file interruption point. It does
not establish same-volume APFS clone failure, every copy instruction, iOS capture or
publication interruption, or physical power/Data Protection durability.

## Same-volume clone destination collision

At app `3b973d66`, LLDB confirmed that the production copyItem path calls the actual
`libsystem_kernel.dylib` clonefileat syscall on the same APFS volume. While stopped
immediately before that syscall, the debugger host created a 37-byte collision file
at the marked disposable candidate's capture/study.store. No register or return value
was replaced. The syscall returned -1; Foundation reported Cocoa 516 / POSIX 17
(File exists), preserving the collision bytes.

Both base and committed-WAL sources subsequently restored all 38 exact records in
two fresh processes. Each retry chose a new candidate and preserved all abandoned
preparation hashes, original/retained family hashes and the frozen fixture. The
second successful reopen left selection bytes unchanged. This proves actual native
clone destination-collision handling, not same-volume ENOSPC or power-loss behavior.

The first base harness selected hold-application-opening, whose top-level error is
unhandled rather than exit 74. LLDB stopped at that synthetic failure and its batch
session exited; PID 16407 was then verified absent. The failed expectation is retained.
A separate recovery driver reopened that same failed source twice without repeating
the collision. The WAL run used inspect-application-payload, which catches the same
production-opener failure and deliberately exits 74. This harness distinction does
not describe a crash in the app's own launch error handling.

Evidence: `.build/Results/Clone-Collision-20261025` and
`Clone-Collision-20261025-WAL`, with debugger transcripts, exact-state reopen logs,
source/preparation receipts and drivers. The probe binary matches the partial-copy
experiment above. Driver SHA-256 values:

- Initial base: `58e546802b913f0ccbb96e2075918e96d985825650629a2a9857962ec62f4006`.
- Base recovery: `5120107a4bf5b0a7927b1ca1b3dc7d6104bc696d46b92b966ca581ca8b84e032`.
- WAL: `be4448beb5b874ed36f994c151b0dc07108232e22d428b4cddbdf4266449c2a4`.
