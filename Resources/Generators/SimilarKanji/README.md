The json files in this directory are from
https://github.com/mwil/wanikani-userscripts/tree/master/wanikani-similar-kanji/db

The Swift generator merges duplicate candidates at their highest score, includes
scored candidates strictly above 0.4 and orders them by descending score. Equal
scores retain source order so regeneration is deterministic.

From Developer/Projects, run:

```sh
mainboard run --as-is usagi-similar-kanji /tmp/visually-similar-kanji.plist
```

The Swift generator writes the binary property list atomically to that path;
stdout contains a text summary only. Do not redirect binary data through task
log capture. Review it before replacing the single bundled catalog:
`Shared/Sources/StudyCore/Resources/visually-similar-kanji.plist`.
The app consumes the committed property list and never needs this generator at runtime.

The retained source database already regenerates a different ordering for 1,594 entries than the bundled historical snapshot. Both the old JSON generator and this file-writing version produce the same 2,380 decoded values. This cleanup preserves the bundled snapshot exactly; regeneration is a reference-data update that needs separate review, not a byte-for-byte rebuild of that snapshot.
