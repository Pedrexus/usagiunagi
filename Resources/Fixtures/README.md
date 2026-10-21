# Levels 1–3 display catalog

Normal account data comes from WaniKani's API through URLSession and is persisted in SwiftData. No Parquet file, conversion pipeline or manual export is required. The unused development `free-levels.parquet` derivative is removed; its historical validation remains below.

The native app's offline preview reads `Shared/Sources/StudyCore/Resources/free-levels-preview.plist` through Foundation. On Mac, Account → Preview free levels 1–3 opens it offline before connecting an account. Demo IDs are negative, account identity is absent and no assignments/answers are invented or uploaded. Small deterministic fixtures still support tests without a network or real exercises.

The [official API](https://docs.api.wanikani.com/20170710/#authentication) requires a personal API token for every request, including subjects. WaniKani recommends [local subject caching](https://docs.api.wanikani.com/20170710/#caching), [conditional requests](https://docs.api.wanikani.com/20170710/#conditional-requests) and [`updated_after`](https://docs.api.wanikani.com/20170710/#leveraging-the-updated_after-filter). Subscription content limits still apply.

The current client downloads complete collections, and `StudyStore.applyDownload` atomically applies them while preserving pending work. Incremental refresh remains separate work: its partial collections must merge without deleting absent rows or advancing cursors before a successful save. Fetch the needed offline study content in advance; avoid requiring a network request for each answer. Keep the existing store owner and direct model queries rather than adding another cache framework.

Captured read-only on 2026-10-18 from the visible subject grids in the user's existing Chrome session:

| Source | Radicals | Kanji | Vocabulary | Total |
| --- | ---: | ---: | ---: | ---: |
| [Level 1](https://www.wanikani.com/level/1) | 25 | 18 | 37 | 80 |
| [Level 2](https://www.wanikani.com/level/2) | 33 | 35 | 79 | 147 |
| [Level 3](https://www.wanikani.com/level/3) | 27 | 30 | 73 | 130 |

All 357 rows contain only level, kind, characters, displayed reading and displayed meaning. The capture's code-point FNV-1a checksum was `638ee6020e061916` before normalizing `radicals` to `radical`. No account stage, unlock status, credentials, user identity, review history or hidden page state was copied. Chrome was returned to its dashboard; no exercises were opened.

These are authentic **display fields**, not complete API subjects. They lack WaniKani IDs, all accepted/auxiliary answers, alternate readings, mnemonics, component relationships, SRS rules and audio. The preview is for browsing and UI mocks; a complete review/lesson fixture still needs an authorized API catalog. WaniKani content is governed separately by [its terms](https://www.wanikani.com/terms); no broader content license is asserted.

## Native catalog export

Settings → Developer options → **Export saved levels 1–3** now uses the same account-bound source as the existing diagnostics action, with a separate public-content projection. Apple's ShareLink/CoreTransferable publishes `usagiunagi-free-levels.plist`; there is no custom share controller, extra runtime dependency or export cache. No export is performed automatically.

`StudyCatalogDocument` format 1 contains `capturedAt` (an ISO 8601 string), `requestedLevels`, native `CatalogSubject` values, optional public SRS systems and public voice-actor metadata. The capture time describes the export, not a verified server-update time. Subjects retain IDs, meaning/reading roles, relationships, image/audio references and teaching fields. Account identity/profile, credentials, personal notes/synonyms, assignments, review history, sessions, queues, preferences, cursors and handoff receipts are excluded. A direct SwiftData model query selects this account's levels 1–3 in level/ID order; hidden subjects are omitted. Empty/sample/missing sources and inconsistent stored IDs/levels refuse export. Missing SRS metadata remains absent rather than becoming invented defaults.

The file describes **saved content in the requested scope**. It does not establish completeness or an official current curriculum. Validate provenance and grading fields before using a genuine export as a test fixture. The current bundled preview remains display-only and byte-exact; its loader does not accept this different document format. No account or exercises were accessed to prepare this feature.

This optional developer sharing action is independent of normal API synchronization. It is not a step users need to take to populate SwiftData or study offline.

### Public-source check — October 21

The focused public search did not verify a complete current source with original IDs and accepted/auxiliary-answer metadata. The [2014 export announcement](https://community.wanikani.com/t/export-of-wanikani-radicals-kanji-and-vocab/6786/2) explicitly dates its corpus to December 2014. The [Anki exporter source](https://github.com/BtbN/Anki-WaniKaniSync/blob/master/importer.py) consumes supplied API subject records; its compressed supporting files provide pitch/phonetic data, not the requested catalog. An anonymous [public kanji page](https://www.wanikani.com/kanji/%E4%B8%80) supplies display information and reading groups, while the inspected HTML lacks explicit accepted-answer/auxiliary-meaning fields. The [official API reference](https://docs.api.wanikani.com/#subjects) defines those semantics and gives illustrative records; examples are not a complete curriculum export. No absence claim is made about every possible public repository, and no content redistribution license is inferred from an API-client code license.

### Historical export validation — `d3b2a20a`

Both native Debug builds pass with zero compiler/analyzer warnings in their summaries. All **560 shared functions / 72 suites** pass on Mac and iPhone, including **843 iPhone executions**, with no skips/failures. Four added export tests preserve exact public fields, alternate/whitelist/blacklist metadata and public SRS/voices, reject wrong levels/hidden/foreign/sample/empty/inconsistent sources, and prove cancellation/export leave every saved account-work field unchanged. Scoped formatting, SwiftLint and parser/UI checks pass without final rewrites. Inventory parses **262/262** files without context issues: production **146 / 21,694** physical lines, tests **111 / 26,205**, tooling **five / 281**. V1 and its frozen fixtures/decoder sources are unchanged.

A disposable Swift package under `/private/tmp/usagi-free-catalog.zDU2Pl` used only an in-memory synthetic account and the actual public export API. Its binary plist converted through Apple's `plutil` and Mainboard's query exporter to **three synthetic rows / three levels / IDs 1001–1003**, with Parquet metadata reporting **ZSTD**. These were pipeline controls, not real WaniKani subjects, and replaced no bundled data. The now-removed 357-row Parquet had SHA `df9846fa93dcb9902aa36da60aaf827e216fb93dcbc3568d3bf2d08d879996a2`; the unchanged native preview remains `b09e54c0b4a010a4cf1c393234524f06997a5e56e0bd529e07a6034f14b52995`.

| Evidence under `.build/Results/` or `.build/Reports/` | SHA-256 |
| --- | --- |
| `build-1880db568bd547bfaa843c74db42936e.build.json` (iPhone) | `449dbd7db9b5601805201e33263da28b642fbe1762bb87b5e0502faf52fbdc11` |
| `build-67ab7889d7a54ae8aedad774bd096342.build.json` (Mac) | `65042da9c95b649a4b32c9347eefe64bb4860ed877d670eb7251b477a3da08ee` |
| `FreeLevelExportSharedTests.log` | `b3944819e0dc1b37e8dc65310d5d99ca5d574d3611cbedbf95b52ed38b2d6b56` |
| `test-c7f23a79f2044fbf8d997812aa4d51a0.tests.json` | `d690a90bb757e6b4be3ded5872416620192ca6c62f985b604e7125f1556c749f` |
| `FreeLevelExportLint.log` | `d9c6e52db3324b606f91312ee0fd7b19532a6d5b644c222305c6b1815e4035d1` |
| `FreeLevelExportInventory.json` | `5cf01d492df18244dd78c6cec79900ed1451348a6a1fd31d24cb6c707d853a67` |
| `FreeLevelExportPipelineBuild.log` | `4e1afd7d3ee30f1939ce745f6d2fc133ef368749b1b72a203b220fa507a3be53` |
| `FreeLevelExportParquetCheck.log` | `109ae25b43786f39f5e53bf6f02e44712f13b39a02ec4d953ac5f655a0692418` |
| `FreeLevelExportParquetMetadata.log` | `d1018c656277dde7776ae9902b6e39c0145ed71266230787fb444cdd5f1af947` |

The exporter source SHA is `957cb0384fa8cd729660aa6fefb5b75522a5cf3b719ac7759ecab8aef364560c`; tests are `8b0542e83c55ab652e6fcd861495ae2d8ac7c610a178c5d7d5938fb65cda1848`. The synthetic plist/JSON/Parquet hashes are respectively `59899546cd9d164f9b8923dcc41dd543178e6e30ef41ddbf4f1f9f8b056ebbb9`, `7f0e373985bf75bd8bf4632735218db61dd4d8828f62e5052d353331ee0d4a16`, `eb92da430a99d5ada2b32391cd16c4ba5f9751e2b0e9f58543378e21b960c712`. Native share-sheet interaction and actual source acquisition remain unverified under the existing GUI restriction; no private account/token/browser access, real exercise, physical capture, signing-configuration change or publication occurred. Broader storage, usability, speech, statistics and physical/watch gates remain open.
