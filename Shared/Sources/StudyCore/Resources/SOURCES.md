# Curriculum data sources

`curricula.plist` is a reduced, combined dataset, distributed under CC BY-SA 4.0. It contains character-to-grade and estimated JLPT mappings only. It contains no user data. App source code remains under the repository's Apache 2.0 license.

- School grades, Jōyō and Jinmeiyō classifications: KANJIDIC2, copyright James William BREEN and the Electronic Dictionary Research and Development Group (EDRDG). Source: https://www.edrdg.org/kanjidic/kanjidic2.xml.gz ; snapshot date recorded in the catalog. Project documentation: https://www.edrdg.org/wiki/index.php/KANJIDIC_Project . License: https://www.edrdg.org/edrdg/licence.html and https://creativecommons.org/licenses/by-sa/4.0/ . Transformations: selected literal and grade fields; omitted dictionary readings, meanings and other classifications. Grades 1–6 total 1,026; Jōyō including grade 8 totals 2,136. Canonical-equivalent Unicode forms are deduplicated, retaining the earliest school grade; otherwise compatibility variants can overwrite a Jōyō classification in Swift dictionaries. Name-use grades are retained in the resource but are not presented as an exam scope.
- Estimated modern JLPT mapping: David Gouveia, kanji-data, commit 00fd7079c3890f430759536f91aa5e854ec0ca4f. https://github.com/davidluzgouveia/kanji-data . Extracted `jlpt_new`, without WaniKani level assignments. Repository license retained in kanji-data-LICENSE.txt. Underlying JLPT lists credited to Jonathan Waller: https://www.tanos.co.uk/jlpt/ . KANJIDIC is also an upstream source of kanji-data. This is community study material, not an official or exhaustive exam specification. Do not substitute old JLPT's four levels for the estimated modern five-level mapping.
- JLPT explains why it does not publish current kanji/vocabulary/grammar lists: https://www.jlpt.jp/e/faq/ . Coverage cannot predict passing a JLPT level.
- Kanji Kentei elementary targets and level 2 use the published school-grade/Jōyō scopes: https://www.kanken.or.jp/kanken/grades/meyasucheck/ . Intermediate levels 4, 3 and pre-2 are intentionally absent because exact subsets have not been sourced. No claims about handwriting, stroke order, compound formation or passing are made.

## Refresh procedure

Refresh KANJIDIC2 before each release, and inspect the JLPT source for corrections. Download the two sources, decompress KANJIDIC2, and run:

    swift Resources/Generators/update-curricula.swift /tmp/kanjidic2.xml /tmp/kanji.json Shared/Sources/StudyCore/Resources/curricula.plist

If changing the JLPT revision, update the generator and this attribution. Run StudyCoreTests; changed official totals require review rather than silently accepting incompatible data. The application exposes inline Sources details with the source snapshot date and license links.

## Legacy study supplements

`old-mnemonics.plist` and `visually-similar-kanji.plist` are inherited from davidsansome/tsurukame, originally in `ios/WaniKaniAPI/...` and later `App/WaniKaniAPI/Sources/WaniKaniAPI/Resources`. `StudySubjectSupplements` now owns one typed, immutable catalog for both the shared reader and the temporary legacy API module. The two duplicate legacy files and their resource directory are deleted after verifying byte identity, removing 172,418 bytes without changing content. All 79 mnemonic and 2,380 similar-kanji entries are covered by canonical SHA-256 checks in Swift Testing. Original resource digests are `995333a5eaef7696f1395192ea7e5c859f07b512aafe40451841aaf70323f55e` and `156cea19f47e434e7fa0cb3e864b63f3e47ac1b71b3c9a57f89dff01a3ffc640`, respectively. These resources preserve study content; they are not mock API replies.

## WaniKani display preview

`free-levels-preview.plist` contains 357 displayed subject references from the first three level pages, captured read-only on 2026-10-18. It includes only characters, displayed readings/meanings, level and kind, with no account progress or API identifiers. See [provenance, counts and limits](../../../../Resources/Fixtures/README.md). It is not a complete grading catalog and is not used for authenticated reviews. WaniKani content retains its separate terms; the app's Apache license does not grant a new license to that content.

## Mnemonic artwork index

`artwork.plist` preserves all 469 subject-to-image paths from the fork's former `App/Features/Catalog/ArtworkManager.swift`. It is a binary Apple property list, replacing the large Swift lookup table without downloading or redistributing image pixels. The images are @AmandaBear's artwork, published in [the WaniKani community thread](https://community.wanikani.com/t/wk-mnemonic-art-for-kanji-levels-1-7-radical-levels-1-10/47656); the original lookup was adapted from [WaniKani Mnemonic Artwork](https://greasyfork.org/en/scripts/418774-wanikani-mnemonic-artwork). Image rights remain with their authors. The shared view retains visible attribution and the original public image URLs.

The sorted UTF-8 `subjectID:path\n` representation has SHA-256 `00d4f38cd8546f92f190bd71fd79f4d9126a799eab9150a71930f567e1758b40`; Swift Testing verifies every entry against this digest. Artwork is optional and never appears before the meaning is revealed. Cached requests use the platform URL cache; no reachability flag hides an otherwise cached image.

All four bundled reference catalogs use binary Apple property lists, read with Foundation Codable through one `StudyResources` loader. The JSON-to-property-list conversion verifies identical sorted JSON for every original value, including array order, Unicode, metadata and optional fields. This changes storage format only; it does not remove reference data, create a database or replace API JSON. Original JSON digests above identify historical inputs. See [conversion validation](../../../../Docs/Validation/2026-10-20-native-catalogs.json).
