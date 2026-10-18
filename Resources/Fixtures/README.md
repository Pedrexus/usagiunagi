# Levels 1–3 display catalog

`free-levels.parquet` is a Zstandard-compressed development reference. The native app reads the matching compact `Shared/Sources/StudyCore/Resources/free-levels-preview.json` through Foundation; no Arrow/Parquet runtime is added to the app. On Mac, Account → Preview free levels 1–3 opens it offline. Demo IDs are negative, account identity is absent and no assignments/answers are invented or uploaded.

Captured read-only on 2026-10-18 from the visible subject grids in the user's existing Chrome session:

| Source | Radicals | Kanji | Vocabulary | Total |
| --- | ---: | ---: | ---: | ---: |
| [Level 1](https://www.wanikani.com/level/1) | 25 | 18 | 37 | 80 |
| [Level 2](https://www.wanikani.com/level/2) | 33 | 35 | 79 | 147 |
| [Level 3](https://www.wanikani.com/level/3) | 27 | 30 | 73 | 130 |

All 357 rows contain only level, kind, characters, displayed reading and displayed meaning. The capture's code-point FNV-1a checksum was `638ee6020e061916` before normalizing `radicals` to `radical`. No account stage, unlock status, credentials, user identity, review history or hidden page state was copied. Chrome was returned to its dashboard; no exercises were opened.

These are authentic **display fields**, not complete API subjects. They lack WaniKani IDs, all accepted/auxiliary answers, alternate readings, mnemonics, component relationships, SRS rules and audio. The preview is for browsing and UI mocks; a complete review/lesson fixture still needs an authorized API catalog. WaniKani content is governed separately by [its terms](https://www.wanikani.com/terms); no broader content license is asserted.

Regenerate the development Parquet using Mainboard's existing Zstandard exporter, from this repository:

```sh
mainboard query "SELECT * FROM read_json_auto('Shared/Sources/StudyCore/Resources/free-levels-preview.json')" --out /tmp/free-levels.parquet
```

The exporter refuses overwriting evidence. Inspect row counts with `read_parquet` and the compression column in `parquet_metadata` before replacing the committed development artifact. Updates require a fresh visible capture and matching row-count/integrity review, rather than guessing curriculum changes.
