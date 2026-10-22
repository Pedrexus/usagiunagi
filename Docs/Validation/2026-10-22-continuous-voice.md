# Continuous voice review — October 22

## Behavior and boundaries

Tap the review microphone once to enter a session-local voice mode. The current subject
and prompt remain visible. English meanings and Japanese readings select their own
recognition locale. Live text is a preview; after 1.2 seconds without a nonempty recognizer
update, the controller requests finalization. Only the completed final text can reach
the existing grader, question identity/revision check, SwiftData transaction and outbox.
The next question starts listening after a 650 ms feedback interval. The app does not
persist or automatically restore microphone activation across launches/backgrounding.

Following the owner's clarification, a wrong answer shows its correction for three
seconds, then invokes ordinary saved-session advance. Its original mistake penalty and
required retry remain intact. A grading hint repeats the same question. No routine stop,
check, correction-choice or continue tap is required while voice mode is running.

A Japanese transcript containing kanji/numbers cannot itself submit as a reading. If the
recognizer supplies exactly one complete kana interpretation, continuous review uses it
without looking at the answer key. Multiple/no kana alternatives cause another listening
attempt after three seconds without grading. Empty final recognition also repeats.
The single-answer practice sheet retains explicit transcript selection/confirmation.
No generated text-to-kana conversion, answer-key-conditioned alternative selection,
pronunciation scoring or speech command guessing is introduced. Pronunciation autoplay
pauses during voice review so the app cannot dictate its own answer into the microphone.

Keyboard use, navigation to previous information, end-session dialogs and backgrounding
cancel automation. Save errors stop voice rather than restart capture behind an error.
First-time microphone permission and missing language-model assets are explicit setup;
denial, unsupported speech and fatal errors retain keyboard recovery. Both English and
Japanese models must be set up for a hands-free bilingual run.

The shared controls also serve the existing single-answer katakana practice sheet, where
the transcript still requires confirmation. Captures retain the mandatory shared audio
lease until cancellation/finalization cleanup completes. Only then can a submission run.
Disappearing controls and inactive scenes cancel pending submissions and capture; every
new question gets a new controller/capture identity. No schema, dependency or platform
layout branch is added.

## Apple documentation checked

The installed Xcode 27 Speech interfaces and current official documentation establish
that [volatile results](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption)
are tentative; they are enabled for responsive preview without the accuracy-reducing
`fastResults` option. Japanese keeps recognizer alternatives. The final-result-only
`VoiceAnswerDraft` remains the grading boundary.

The [iOS 27 Speech update](https://developer.apple.com/documentation/updates/speech)
introduces the native `CaptureInputSequenceProvider` already used here. The preferred
recognizer remains `SpeechTranscriber` with tentative results and Japanese alternatives;
when its hardware/locale is unavailable, Apple's on-device
[DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)
uses short-form hints. Both share the provider/analyzer/resource lifecycle. Locale follows
the question, English for meanings and Japanese for readings. This does not establish
automatic mixed-language recognition within one answer.

[SpeechDetector.Result](https://developer.apple.com/documentation/speech/speechdetector/result)
still documents results as supporting error handling from the VAD model. Accordingly,
this implementation does not assume a reliable public end-of-utterance event. The
1.2-second endpoint is a debounce of transcript updates, not measured acoustic silence.
Physical-device timing, long answers, environmental noise, interruptions and route
changes still need acceptance before claiming a polished real-microphone experience.

## Duolingo and iOS 27 AI findings

[Duolingo's current speaking overview](https://blog.duolingo.com/covering-all-the-bases-duolingos-approach-to-speaking-skills/)
documents spoken answers instead of typing, speaking-only practice and conversational
features. Its [older audio-lesson experiment](https://blog.duolingo.com/how-weve-improved-the-duolingo-learning-experience-this-year-and-a-sneak-peek-toward-2020/)
describes hands-free lessons; that historical article does not establish current
availability across courses. We use the interaction as inspiration without claiming
Duolingo's recognition implementation is available to us.

The [iOS 27 Foundation Models changes](https://developer.apple.com/documentation/updates/foundationmodels)
add improved on-device models, provider protocols, dynamic profiles, image input and
Private Cloud Compute. [Multilingual Foundation Models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
support locale-aware text generation with runtime capability checks. Text generation
cannot recover a lost acoustic distinction from an ambiguous kanji transcript. It is
not added to recognition/grading or allowed to replace WaniKani truth.

Useful optional follow-ups are post-answer mnemonic/mistake explanations, Siri/App
Intents for starting or pausing study, and the new
[Evaluations framework](https://developer.apple.com/documentation/updates) for Japanese/English
output regression datasets. [Core AI](https://developer.apple.com/ios/whats-new) can host
a custom on-device model if measured limitations later justify maintaining one. None is
required for this loop; no AI dependency, cloud request, generated accepted answer or
automatic model download is added.

## Manual checks before final tests

Only the explicit memory-only `--review-fixture` app is launched. No real account,
WaniKani exercise, microphone permission, speech model download or signed service is used.

The first phone check verifies inline English listening, ordinary grading, automatic
Japanese listening, refusal of the final kanji transcript `一`, and keyboard recovery.
It exposes an oversized correction field; native intrinsic sizing repairs it. A second
isolated launch with tentative fixture speech completes both sides of `一` and reaches
the 100% saved review summary after one microphone tap and no further study actions.
The new native correction assertion also limits the field height at normal text size.

After the no-tap clarification, a new isolated session deliberately recognizes `two`
for the meaning of `一`. One microphone tap is followed by automatic progression and
the saved summary, without further study taps. The summary retains 0% / 0 of 1 correct
and lists Meaning missed. The fixture's later reading supplies `一` with the independent
kana interpretation `いち`, exercising that automatic selection through ordinary grading.

## Validation receipts

The owner reiterates “Leave tests for the end.” Further automated testing is deferred;
the in-flight phone lane is deliberately canceled and will need a final-stage rerun.
Already completed checks on the final source, before that instruction:

- `ContinuousVoice-FinalNoTapSharedMac-20261022.log`: 587 passing functions, comprising
  StudyUI 111, StudySpeech 15, StudyPersistence 207 and StudyCore 254.
- Unsigned Release Mac `build-47d8e83904694f7e8fd9124ee26173ab.xcresult` and iPhone
  simulator `build-e5782e71bb854795a09c5a5f3bc562ef.xcresult`: successful terminal
  results, with zero compiler/analyzer errors or warnings in the build summaries.
  The separate App Intents metadata-extractor notice remains in the build logs.
- `ContinuousVoice-FinalNoTapMacBundle-20261022.json` and
  `ContinuousVoice-FinalNoTapIOSBundle-20261022.json`: packaged-app policies pass with
  no violations. These are unsigned products, not signed-service acceptance.
- Scoped formatting checks pass on all eight changed Swift files without rewrites.
  Full formatting checks inspect 448 files and fail only on the 30 preserved owner-file
  diagnostics. No owner file is formatted or included in this change.
- Rules finish with 231 findings across 98 rules, including the additional advisory
  `ALL-CONT0004` at `VoiceAnswerControls` (nesting 4, ceiling 3). No suppression is added;
  a completed inventory is not a clean rule gate.
- `ContinuousVoice-LocaleReadinessMac-20261022.log`: a read-only runtime query finds
  `SpeechTranscriber.isAvailable` and equivalent English/Japanese locales on both
  transcribers on this Mac. It does not exercise a microphone, download a model or
  establish physical-iPhone support/recognition quality.

The exact eight Swift sources and frozen V1 are hashed in
`.build/Reports/ContinuousVoice-FinalNoTapSource-20261022.sha256`; all match after the
checks. The three protected owner-file hashes also match their original receipt.
Logs and bundles live under the ignored `.build/Results` and `.build/Reports` folders.

The final five-case phone selection is retained as
`test-7694698a1e9b48aebe63e8166fc37c86.xcresult`, with its log
`ContinuousVoice-FinalNoTapNativeIOS-20261022.log`. The collected process exits 73 after
an explicit interrupt and `TEST INTERRUPTED`: one katakana practice pass and one canceled
continuous-review case, with failure text “Testing was canceled.” The other three selected
methods do not execute. The build summary succeeds with zero compiler/analyzer diagnostics;
the test summary is unsuccessful. Xcode's cancellation assertion/diagnostic-collection
messages remain in the log. This does not accept the five-case selection or the complete
69-method phone gate, and the canceled case is not treated as an app failure. No replacement
test job is started.

The initial Mac compile fails because the practice sheet still needs `VoiceAnswerRequest`;
that practice-only request is restored before the successful renewed compile. The first
scoped lint correctly rejects nonprivate SwiftUI-owned state; the controls now use private
state and an explicit initializer. Neither failed trial is treated as acceptance.

The first focused phone lane, `test-36fbc9267be14706935edd9543f254c6.xcresult`, is also
explicitly canceled during the owner's no-tap/research clarification and save-error
review. Its native-katakana method records cancellation; it does not accept or establish
a functional failure in the revised hands-free source.

The prior `Ownership-FullPhoneIOS-20261022.log` run builds from `8b5df5e1` plus the three
protected owner edits. Its executable hashes remain unchanged throughout its three
passing methods. It is intentionally interrupted to prioritize the new requested voice
flow; `test-13fba199792740adaa14b89c878612be.xcresult` reports three passes and one canceled
case, not a successful full lane. Its receipt and binary hashes remain retained.

The broader task ledger, storage gates, protected-file lint failures and hosted Mainboard
publication limitation remain open independently of this feature.
