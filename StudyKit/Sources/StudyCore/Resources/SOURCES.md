# Curriculum data sources

`curricula.json` is a reduced, combined dataset, distributed under CC BY-SA 4.0. It contains character-to-grade and estimated JLPT mappings only. It contains no user data. App source code remains under the repository's Apache 2.0 license.

- School grades, Jōyō and Jinmeiyō classifications: KANJIDIC2, copyright James William BREEN and the Electronic Dictionary Research and Development Group (EDRDG). Source: https://www.edrdg.org/kanjidic/kanjidic2.xml.gz ; snapshot date recorded in JSON. Project documentation: https://www.edrdg.org/wiki/index.php/KANJIDIC_Project . License: https://www.edrdg.org/edrdg/licence.html and https://creativecommons.org/licenses/by-sa/4.0/ . Transformations: selected literal and grade fields; omitted dictionary readings, meanings and other classifications. Grades 1–6 total 1,026; Jōyō including grade 8 totals 2,136. Canonical-equivalent Unicode forms are deduplicated, retaining the earliest school grade; otherwise compatibility variants can overwrite a Jōyō classification in Swift dictionaries. Name-use grades are retained in the resource but are not presented as an exam scope.
- Estimated modern JLPT mapping: David Gouveia, kanji-data, commit 00fd7079c3890f430759536f91aa5e854ec0ca4f. https://github.com/davidluzgouveia/kanji-data . Extracted `jlpt_new`, without WaniKani level assignments. Repository license retained in kanji-data-LICENSE.txt. Underlying JLPT lists credited to Jonathan Waller: https://www.tanos.co.uk/jlpt/ . KANJIDIC is also an upstream source of kanji-data. This is community study material, not an official or exhaustive exam specification. Do not substitute old JLPT's four levels for the estimated modern five-level mapping.
- JLPT explains why it does not publish current kanji/vocabulary/grammar lists: https://www.jlpt.jp/e/faq/ . Coverage cannot predict passing a JLPT level.
- Kanji Kentei elementary targets and level 2 use the published school-grade/Jōyō scopes: https://www.kanken.or.jp/kanken/grades/meyasucheck/ . Intermediate levels 4, 3 and pre-2 are intentionally absent because exact subsets have not been sourced. No claims about handwriting, stroke order, compound formation or passing are made.

## Refresh procedure

Refresh KANJIDIC2 before each release, and inspect the JLPT source for corrections. Download the two sources, decompress KANJIDIC2, and run:

    swift tools/update-curricula.swift /tmp/kanjidic2.xml /tmp/kanji.json StudyKit/Sources/StudyCore/Resources/curricula.json

If changing the JLPT revision, update the generator and this attribution. Run StudyCoreTests; changed official totals require review rather than silently accepting incompatible data. The application exposes a Sources sheet with the source snapshot date and license links.

## Legacy study supplements

`old-mnemonics.json` and `visually-similar-kanji.json` are byte-identical copies of this fork's existing `ios/WaniKaniAPI/Sources/WaniKaniAPI/Resources` files, inherited from davidsansome/tsurukame. They preserve the legacy radical mnemonic and similar-kanji features in the native catalog reader. The original resource copies remain temporarily because the active iOS legacy API module still uses them; remove those copies when that module's callers are retired.
