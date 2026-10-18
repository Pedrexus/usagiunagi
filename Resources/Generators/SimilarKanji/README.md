The json files in this directory are from
https://github.com/mwil/wanikani-userscripts/tree/master/wanikani-similar-kanji/db

The Swift generator merges duplicate candidates at their highest score, includes
scored candidates strictly above 0.4 and orders them by descending score. Equal
scores retain source order so regeneration is deterministic.

From Developer/Projects, run `mainboard run --as-is usagi-similar-kanji` and redirect
stdout to a temporary JSON file. Review it before replacing both bundled copies:
`App/WaniKaniAPI/Sources/WaniKaniAPI/Resources/visually-similar-kanji.json` and
`Shared/Sources/StudyCore/Resources/visually-similar-kanji.json`.
The app consumes the committed JSON and never needs this generator at runtime.
