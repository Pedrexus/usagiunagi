# Watch voice reviews — October 22

The later [all-device voice checkpoint](../Validation/2026-10-22-voice-devices.md) supersedes
the test-deferred status below and adds protocol 2, native radical bitmaps, exclusive audio
ownership, pause fences and speech-corroborated hiragana conversion. Earlier receipts retain
their original source scope; signed paired capture remains unaccepted.

## Interaction and ownership

The Watch opens a native SwiftUI voice-review screen; complication settings remain behind
its gear button. Start once to request microphone permission and resume the phone's saved
review session. The Watch shows the subject and Meaning/Reading prompt, records one short
answer, waits for the phone's durable grading response, gives haptic feedback and proceeds.
Pause stays in the navigation bar. There is no per-answer dictation sheet, check button,
keyboard or continue tap. Subject text scales with Dynamic Type. Image-only radicals
must load successfully before capture starts; an unavailable image pauses without grading.

English and Japanese follow the question through the same `VoiceReviewController`,
`VoiceAnswerDraft` and Apple transcriber selection as phone reviews. `AppleVoiceCapture`
also accepts a recorded file, bypassing the phone microphone/audio session; file analysis
finishes through the final-result stream. Only finalized text and an independent, single
unambiguous kana alternative can submit. Ambiguous readings and empty final results repeat
automatically. Normal grading hints repeat; mistakes show their correction for three
seconds and use ordinary saved-session advance, retaining the original penalty.

The phone is the only writer. `WatchReviewHost` uses existing `StudyStore` review methods,
the current account/question and expected saved revision. New Watch sessions use typed
grading with Anki off; an existing Anki, lesson or practice session must finish on the
phone first. No token, pre-grading answer key, separate Watch database, schema change or
dependency is introduced; corrections appear only after grading. Saved answers enter
the existing durable WaniKani outbox. The Watch says
saved on iPhone, never synced with WaniKani without an upload receipt.

## Transport, cancellation and audio limits

Versioned binary property lists use the existing WatchConnectivity owner. Each message
has a request ID and each run a different ID; replies reach only the matching pending
request. Answer/advance requests also require the saved revision. The Watch never
automatically retransmits an answer after an uncertain response: Resume reloads the
authoritative session. A late reply is ignored after cancellation. The phone rejects
overlapping operations and stale account/run/revision input. Pause can cancel pending
recognition. An answer already committed before Pause reaches the phone remains saved.

The Watch records mono AAC at 16 kHz / 16 kbit/s. Metering ends an answer after 1.2 seconds
below −42 dBFS following audible input. This is a level threshold, not a learned speech
detector; quiet voices/noise require device tuning. After ten seconds without audible
input, the empty clip is discarded and a revision-checked refresh rearms listening
automatically; thinking time needs no Resume tap or grading. A fifteen-second answer
pauses without grading truncated audio. Audio is capped at
48,000 bytes and the whole message at 56,000 bytes. Phone recognition has a fifteen-second
bound; Watch responses have a twenty-five-second bound. The scene must remain active.
Background/inactive scenes, leaving the view, interruption or setup/connection failure
pause capture. No unrelated workout or extended-runtime entitlement is requested.

Temporary audio files are deleted after completion/cancellation. Phone temporary audio
uses protection until first authentication; persistent credential accessibility is not
weakened. A cold locked phone may require unlocking/opening the app to restore protected
credentials/data. System background execution and wrist-down behavior need signed paired
device acceptance. Both language models must already be installed using phone voice input;
the Watch does not silently download them. A sixty-second expiring study lease defers
catalog reads and learning-preference imports. Pause/completion clears it; losing the
Watch cannot defer those services indefinitely.
The same lease holds the shared phone audio owner's voice-input token, stopping app
pronunciation/autoplay while the Watch is listening. It cannot supply its own spoken
answer from a nearby iPhone. Pause/completion/expiry releases only that run's token.

## Apple Watch Series 12 research

The owner has Series 12. Its new
[Audio Intelligence features](https://support.apple.com/en-us/148354) include the upcoming
English-first Live Rewind/Siri Recap beta. These system features do not establish a
continuous multilingual app recognizer. Apple says Live Rewind does not continuously
transcribe in the background. Its [Series 12 announcement](https://www.apple.com/newsroom/2026/09/introducing-apple-watch-series-12-with-the-all-new-health-sensing-system/)
describes raw Secure Exclave audio as inaccessible to apps.

The installed Xcode 27 Speech interface marks `SpeechAnalyzer`, `SpeechTranscriber` and
`DictationTranscriber` unavailable on watchOS; the Watch SDK has no Speech framework.
Apple's [SpeechAnalyzer overview](https://developer.apple.com/videos/play/wwdc2025/277/)
explains the exclusion. Keyboard dictation remains available, but its system text-entry
UI does not meet the requested automatic bilingual loop.

The supported path uses native [AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder)
on Watch and [file analysis](https://developer.apple.com/documentation/speech/speechanalyzer/start(inputaudiofile:finishafterfile:))
with on-device Speech on the phone. Apple's
[WatchConnectivity documentation](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessagedata(_:replyhandler:errorhandler:))
permits a foreground Watch message to wake the iPhone in the background. Delivery and
indefinite background runtime are not guaranteed. No server recognition, private API,
Siri transcript access, custom model or Foundation Models grading is introduced.

## Build and manual evidence

Automated tests remain deferred at the owner's request. No new test job, real-account
review, microphone permission grant, model download, signing or distribution is performed.
Build/source evidence does not accept the audio loop.

Initial builds expose the SDK's non-Sendable reply callback boundary. A direct `@Sendable`
witness and a Mutex bridge fail compiler checks. Final transport uses correlated data
messages in each direction; no unchecked conformance, preconcurrency import, suppression
or weaker compiler setting is added. The failed trials remain in `.build/Results`.

The first manual Series 12 simulator install catches an existing packaging defect:
`.watchapp.c.widgets` is rejected because the unified Watch host's child suffix contains
a dot. The unpublished widget becomes `.watchapp.widgets`; shipping iPhone/Watch identities
and the App Group remain unchanged. The installed-face migrator reads the corrected
identifier from Info.plist. All Watch targets now require watchOS 27. Signed provisioning
and installed-face upgrade remain separate gates; no service is registered or published.

Final collected receipts, all under `.build/Results`:

- Watch Debug: `WatchVoice-FinalBuildWatch-VisibleStart-20261022.log`, bundle
  `build-a3cf1773569a4e98b7cf4ad43ce17ba6.xcresult`, terminal exit 0. The later quiet-gap
  rearm builds are recorded separately below.
- iPhone Debug including embedded Watch/widget: `WatchVoice-FinalBuildIOS-VisibleStart-20261022.log`,
  bundle `build-b197cb7717c24c50ba3fddaa74f45841.xcresult`, terminal exit 0.
- Shared Mac Release: `WatchVoice-FinalReleaseMac-20261022.log`, bundle
  `build-0e6018fb36314b10a97f564604a319dc.xcresult`, terminal exit 0. Subsequent changes
  affect only the Watch UI/child identifier; Mac's shared Swift sources are unchanged.
- All three build summaries have zero compiler/analyzer warnings/errors. The separate
  App Intents metadata-extraction notice remains in the logs.
- `WatchVoice-FinalRules-VisibleStart-20261022.log`: 234 findings / 98 rules, terminal
  exit 0 for the inventory. Three new `ALL-FUNC0008` complexity advisories concern the
  host request method and Watch capture/loop; this is not a clean rule gate. Nothing is
  suppressed. Earlier protected formatting failures retain their recorded scope.
- Scoped source/document checks are recorded in `WatchVoice-CommitLint-20261022.log`.
  No source or dependency repair is hidden in a test rerun.

One direct Mac/rules invocation initially uses the global Command Line Tools selection
and fails before compilation/SwiftParser. Renewed commands use the declared Mainboard
environment and succeed without changing global Xcode selection. All failed compiler,
invocation and installer trials remain retained.

The isolated, unpaired simulator is `Usagi Voice Watch Series 12`, 42 mm, watchOS 27,
ID `7745CF39-9A03-4873-B017-09CB1C7C20B5`. Final install and launch logs ending
`VisibleStart-20261022.log` collect exit 0. CUA screenshots in the conversation inspect
the initial screen, Settings and return. The first layout hides Start below its introduction;
a native bottom-inset trial overlaps text. Final Start/Resume is the first compact content
row, fully visible without scrolling, with brief instructions and the gear still reachable.
No Start, microphone permission, data-source change, pairing or exercise is performed.
This accepts local install/launch and the idle/settings subset, not voice-loop behavior.

The final quiet-gap adjustment discards ten-second silent clips and refreshes the same
revision automatically, keeping thinking time hands-free. It changes recording/transport
behavior, not the inspected entry/settings layout. `WatchVoice-FinalBuildWatch-Rearm-20261022.log`
and `WatchVoice-FinalBuildIOS-Rearm-20261022.log` collect exit 0, with zero compiler/analyzer
diagnostics, in `build-2c1f0b01609d467c89d163caa07fc19f.xcresult` and
`build-88746c1fdcfc452fac95e6ce2af80554.xcresult`. The final phone-only routing uses an
exhaustive action switch so future actions cannot silently become refreshes:
`WatchVoice-FinalBuildIOS-Routing-20261022.log`,
`build-e96bb6a31b384dc9987341bbffadc870.xcresult`, exit 0, zero compiler/analyzer
diagnostics. The Watch executable is unchanged from Rearm. Final source checks use
`WatchVoice-FinalRules-Routing-20261022.log` (234 findings / 98 rules, exit 0 inventory)
and `WatchVoice-CommitLint-Final-20261022.log` (15 files, no rewrites/failures).
No audio behavior is accepted from earlier screenshots. The final product is installed
and launched again for the current idle-screen capture; its separate manual logs end
`Rearm-20261022.log`.

The final phone audio-ownership safeguard compiles in
`WatchVoice-FinalBuildIOS-AudioOwnership-20261022.log`,
`build-19ba309eda7d4ef1ad999bc647ec91d9.xcresult`: exit 0, zero compiler/analyzer
diagnostics. Final checks of that source are
`WatchVoice-FinalRules-AudioOwnership-20261022.log` and
`WatchVoice-CommitLint-AudioOwnership-20261022.log`. The Watch/Mac executables are
unchanged by this phone-only edit. Paired audio suppression still needs device acceptance.

`.build/Reports/WatchVoice-FinalSource-20261022.sha256` binds the eleven changed Swift
files, Watch plist/project and frozen V1. The three protected owner-file hashes and V1's
`538e50dd4e3d3192be488bad568ab67b2990925d937f62aedba0bcf307b0f5f4` remain unchanged.

## Final-stage acceptance still required

- Add/run native Watch/phone coverage for both languages, correct and wrong answers,
  hints, unclear kana, empty results, stale/replayed requests and lost replies.
- Check pause during recognition/save, rapid resume, concurrent phone study,
  disconnect/reconnect, account changes and background-expiry recovery.
- On the physical Series 12, check permissions/model setup, quiet/noisy speech, haptics,
  routes, latency, battery, wrist-down behavior and a locked/cold phone.
- Inspect long vocabulary, radicals, small screens, large text and VoiceOver.
- Verify signed companion/widget installation, App Group access, original face migration,
  preserved store upgrades and exact WaniKani outbox/upload behavior.
