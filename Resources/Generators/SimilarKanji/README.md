The binary Apple property lists in this directory preserve the decoded JSON source data from
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

The October 20 source-format cleanup preserves all six decoded inputs exactly, including Unicode, numeric precision and array order. Source files shrink from 10,482,065 to 6,263,030 bytes (see the exact validation receipt for final totals). The generator reads Double scores from the property lists and explicitly applies the original Float rounding before thresholding/merging/sorting; all 2,380 regenerated strings and candidate orderings match the pre-conversion generator. The committed runtime supplement is unchanged. See [validation](../../../Docs/Validation/2026-10-20-native-cleanup.json).
