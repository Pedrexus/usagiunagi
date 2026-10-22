# Voice across devices — October 22

This follows `597a374c` on `codex/swiftui-27-curriculum`. The owner requested an all-device
voice check, then a Japanese-to-hiragana conversion engine. This checkpoint does not
close the broader modernization or physical-device acceptance tasks.

## Implementation

- The shared microphone owner grants one exclusive token. Another voice session cannot
  steal it, and a stale release cannot clear its replacement. Capture failures release
  hardware before releasing that token; automatic retries await the same cleanup.
- A manual start wins over delayed automatic startup. Leaving/inactivating the view
  cancels pending starts. Same-question hints create a fresh voice attempt, so exact
  meaning/reading hints cannot strand continuous mode. Mistakes retain normal grading.
- Watch requests fence account, run, generation and saved revision after asynchronous
  work. Pause during recognition cleanup cannot submit the uncommitted answer or revive
  the lease. Existing Anki sessions are rejected before starting, including mixed mode.
- Watch protocol 2 sends a bounded transparent PNG for image-only radicals, produced
  from the phone's existing validated SVG cache. Watch does not attempt unsupported SVG
  decoding through ImageIO. Older protocol requests fail with an update message.
- `KanaConverter.hiraganaReading` uses Apple's Japanese CFStringTokenizer and Japanese
  NumberFormatter spell-out for written/numeric forms. Direct kana uses Unicode mapping
  so long marks survive. Input/output/numerals are bounded; unsupported residual text
  is refused. No dependency, custom language model, expected answer or server is used.
- Automatic reading submission prefers recognized kana. A single recognizer alternative
  remains usable; competing alternatives can be resolved when the dictionary candidate
  matches one. Written text alone is insufficient: Japanese spelling loses pronunciation
  information (`生`, `日本`, `一日`), and the native dictionary can be wrong (`2日`).
  Uncorroborated conversion repeats without grading. Recognized kana keeps its hiragana,
  katakana or mixed spelling for display and submission. Hiragana is only the internal
  comparison form; the existing shared grader accepts both scripts, including mixed kana
  and long marks. The controller retains the original transcript as live text.

Apple references: [Japanese tokenizer](https://developer.apple.com/documentation/corefoundation/cfstringtokenizer),
[token transcription](https://developer.apple.com/documentation/corefoundation/kcfstringtokenizerattributelatintranscription),
[native numeral spelling](https://developer.apple.com/documentation/foundation/numberformatter/style/spellout),
[WebPage image export](https://developer.apple.com/documentation/webkit/webpage/exportedcontentconfiguration/image(region:allowtransparentbackground:snapshotwidth:afterscreenupdates:)).
Generic ideograph-to-Latin conversion is unsuitable because it uses Mandarin readings.

## Collected checks

All logs/bundles are retained under `.build/Results`. Tests use isolated synthetic
accounts/transports, not a WaniKani user's exercises. No microphone permission grant,
new model download, real-account launch/review, signing, upload or distribution occurs.

- Shared focused Swift Testing: `VoiceDevices-FinalKanaScriptsTests-20261022.log`
  passes 45 functions across five suites (17 speech; 28 core/audio/conversion/grading).
  Covers finalized/stale speech, language choice, cleanup, ownership, conversion bounds,
  numeral counters, long vowels and independent speech evidence.
- Hosted iPhone: `VoiceDevices-FinalWatchHostKanaTestsIOS-20261022.log` passes seven tests
  with no failures/skips or summary compiler/analyzer warnings/errors. Six exercise the
  real isolated store plus Watch host; one verifies actual WebKit SVG export, dimensions,
  size and transparent/opaque pixels. The bilingual test enqueues one ordinary review
  and refuses replay without contacting WaniKani. Its three reading variants preserve
  `いち`, `イチ` and `イち` through the returned display text and ordinary saved grading.
- Six iPhone journeys pass in `VoiceDevices-PhoneUI-Renewed-20261022.log`; six iPad
  journeys pass in `VoiceDevices-iPadUI-20261022.log`. They cover automatic bilingual
  progression, retained mistake penalties, unclear-kana repeats, exact-meaning hint retries,
  slow hardware cleanup and keyboard fallback. No failures/skips in these renewed runs.
- Five distinct Mac journeys pass: three in `VoiceDevices-MacUI-20261022.log` and the
  two corrected expectations in `VoiceDevices-MacUI-Renewed-20261022.log`. The first run's
  two failures expected “Meaning” where the UI correctly says “Kanji Meaning”; the renewed
  run preserves the same grading/automatic-progression assertions. Production source is
  unchanged between these two Mac runs.
- Mac's native WebKit image export also passes in `VoiceDevices-RadicalExportMac-20261022.log`.
- Real file-fed Mac recognition uses production `AppleVoiceCapture` and the same controller:
  `VoiceDevices-FinalRealRecognitionMac-20261022.log`. English returns “One thing”; Japanese
  returns written `1つ`, alternatives `ひつ`/`ひとつ`, and resolves the answer to `ひとつ`.
  Before conversion, the same local Japanese sample could not submit. This is one recorded
  sample per language, not a live microphone or pronunciation-quality benchmark.
- Current phone/tablet/Mac captures are retained under `VoiceDevices-PhoneCaptures-20261022`,
  `VoiceDevices-iPadCaptures-20261022` and `VoiceDevices-MacCaptures-20261022`. The inline
  listening state was visually inspected on each; this is a narrow visual subset.
- iPhone Release and Watch Debug builds pass in `VoiceDevices-FinalIOSRelease-20261022.log`
  and `VoiceDevices-FinalWatch-KanaScripts-20261022.log`, with no compiler/analyzer warnings
  or errors. Final Mac Release is recorded in `VoiceDevices-FinalMacRelease-KanaScripts-20261022.log`.
- Enforced lint/parser/UI rules pass across 439 files. The broader inventory remains
  211 findings / 98 rules (`VoiceDevices-FinalRules-KanaScripts-20261022.log`); a successful
  inventory process does not mean those advisory findings are resolved.

The first hosted trial (`VoiceDevices-WatchHostTestsIOS-20261022.log`) retains five passes
and two failures: the Anki fixture assumed a randomly selected meaning question, and
WebKit returned an opaque snapshot despite its transparency option. The fixture now fixes
question ordering; the bounded export uses a luminance alpha mask. Neither assertion is
removed. The first conversion trial (`VoiceDevices-HiraganaSharedTests-20261022.log`)
catches Foundation's reverse kana transform expanding `スーパー` to `すうぱあ`;
direct scalar conversion fixes it while keeping the long-vowel assertions.

The first five-method iPhone UI trial (`VoiceDevices-PhoneUI-20261022.log`) passes automatic
bilingual progression and fails four outdated selectors: LabeledContent summary values
were queried as separate text, the correction's capitalization differed, and the native
popover omitted a Cancel button. Renewed checks inspect the named summary accessibility
elements, preserve correction/penalty assertions and use the existing popover dismiss region.

## Physical and broader acceptance still open

File recognition and fixture-driven UI runs do not prove live microphone accuracy, timing
in noise, interruptions or physical-device behavior. The isolated unpaired Watch simulator
cannot accept WatchConnectivity delivery, wrist-down/background execution, phone locking,
permission/model setup, haptics or real paired bilingual capture. Those remain signed
iPhone/Series 12 device gates. The Watch uses foreground recording plus paired-iPhone
recognition because the installed watchOS SDK has no public SpeechAnalyzer/Transcriber.

The full app regression, accessibility/IME, iCloud/WaniKani conflict acceptance, original-app
usability comparison and hosted CI dependency publication remain tracked in `Docs/TASKS.md`.
Frozen V1 and historical fixture writer bytes remain unchanged.
