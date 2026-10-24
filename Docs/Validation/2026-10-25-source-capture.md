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
