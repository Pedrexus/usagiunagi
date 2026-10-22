# Statistics: sources, definitions and limits

Researched 2026-10-17; interface inspection and pace validation updated 2026-10-18. The first implementation uses existing synced WaniKani records; it does not upload account data to another service or change review scheduling.

## Related tools

- [WKStats](https://www.wkstats.com/): useful reference for progress and level pace. The public entry point requires an API token to view a personal dashboard; no authenticated dashboard or personal account was inspected.
- [WaniLog's comparison with WKStats](https://wanilog.com/compare/wkstats): its author's description suggests pace ranges, workload scenarios and trouble-item prioritization. Treat this as a product description, not independent validation of predictive accuracy.
- [WaniKani History / Time Machine](https://community.wanikani.com/t/web-app-wanikani-history-timemachine/56652): historical views demonstrate useful ways to explain progress, but the author's notice about API history restrictions means a complete historical timeline cannot be assumed available.
- [WaniKani API documentation](https://docs.api.wanikani.com/20170710/): authoritative definitions of review statistics, assignments and level progression records. Lifetime counters are not a timestamped sequence of every answer. A level's `passed_at` and `completed_at` have different meanings; the app uses `passed_at` for level pace.

## Implemented calculations

| Display | Definition | Limits |
| --- | --- | --- |
| Reading / meaning accuracy | Sum correct answers divided by sum correct + incorrect, separately per side; exclude hidden statistics | Answer-weighted lifetime rate, not an average of item percentages, recent accuracy, session pass rate or a retention estimate. Pending local uploads are excluded. |
| Due now | Unique active assignments with valid `available_at <= now`; stages 1–8 | Based on the cached server schedule. Hidden while uploads are pending or vacation is active. |
| Next seven days | Each active assignment's next future date, grouped by local calendar day, starting today | Does not recursively simulate SRS repetitions, new lessons or errors. A lower bound on scheduled work, not a total workload prediction. Calendar boundaries use calendar arithmetic rather than fixed 24-hour days. |
| Typical pace | Median unlocked-to-passed duration of up to 8 latest passed levels, excluding levels 1–2 and recorded abandoned/pre-reset attempts; at least 3 samples | Includes breaks. Incomplete reset history or changes in study habits may still bias the sample. |
| Pace range | Linearly interpolated 25th and 75th percentiles of those durations | Describes the middle half of observed pace. **Not a confidence or prediction interval.** |
| Past pace check | Reconstruct up to 8 recent completed-level estimates from up to 8 earlier levels that had passed by each target level’s unlock time; require 3 training levels per estimate and 3 held-out levels | Shows mean absolute duration/date error and observed quartile-band hits. Later completions cannot train earlier estimates. Uses currently available level/reset records, not a complete historical account snapshot or stored forecasts. |
| Next-level scenario | Current level unlock time + those two durations | Requires a known active level, no pending uploads/vacation, level below 60 and current elapsed time below the lower duration. Otherwise no date is shown. Does not model critical-path kanji or level-specific minimum times. |
| Focus next | Active, visible items with at least 5 answers and 2 errors on a side; use the worse eligible side | Priority score is `(errors + 1) / (answers + 2) / sqrt(currentCorrectStreak + 1)`. Zero streak is valid. Radicals have no reading side. This is a heuristic, not an estimated failure probability. |

The screen shows counts and relevant assumptions. Focus rows open existing subject details. Sample-data mode is visibly labelled and uses synthetic history; it must not be presented as the user's actual performance.

## Making forecasts more credible later

Keep exact schedules separate from conditional forecasts. Collect consented local review-event history with timestamps, result, stage and lesson choices before claiming recent trends or fitting a model. A local history will be incomplete for reviews performed on other clients unless the API supplies them. The [current API contract](https://docs.api.wanikani.com/20170710/#create-a-review) explicitly says individual reviews are no longer persisted and review creation returns an unpersisted object with ID zero; full remote review history must not be assumed available.

The current median baseline is now checked chronologically against held-out completed levels. Compare richer candidate forecasts against that baseline on the same held-out periods. Compare against a simple median-pace baseline. Report absolute date/workload error, sample size, and interval coverage; test resets, long breaks, fast levels and habit changes separately. Do not label a percentile band “80% confidence” without calibration. A useful next iteration would simulate known SRS intervals and critical-path kanji under explicit lesson/review scenarios, then compare those scenarios with observed outcomes.

## Validation

`StudyStatisticsTest` covers empty data, weighted accuracy, hidden subjects, duplicate assignments, lesson/burned exclusion, missing due dates, minimum focus evidence, zero/recovery streaks, median/quartile arithmetic, vacation/overdue scenarios, resets and duplicate level records. Existing grading/kana tests remain enabled. `StudyPaceValidationTests` covers stable pace, insufficient evidence, changes in habits, no future leakage, overlapping records, bounded training/evaluation windows, resets, duplicates, invalid dates and vacation. Native Mac UI acceptance checks the displayed error, inline plot expansion and collapse, without opening a sheet. All acceptance data is synthetic; no live account exercise is used.

Simulator sample-data checks do not establish real-account sync correctness, prediction calibration or physical-device input behavior. No such claims are made.

## Curriculum charts and study targets

The shared SwiftUI dashboard separates Progress, Coverage and Focus. Progress plots SRS stages, meaning/reading accuracy, next scheduled reviews and recent level durations. Coverage uses horizontal stacked bars, configurable Started/Guru+/Master+/Burned thresholds, exact counts, and inline expandable grids of remaining kanji. Chart interaction never presents coverage sheets. Expanded counts use the current threshold and saved snapshot rather than a captured modal value. Reference lists ship in the StudyCore resource bundle; viewing coverage needs no download. Colored kanji open saved subject details; gray kanji remain visible when outside the synced catalog. Focus exposes the underlying error counts and recovery streak.

The design was checked against the current [WaniKani public homepage](https://www.wanikani.com/), including its imagery. The app borrows clear hierarchy and WaniKani's radical blue, kanji pink and vocabulary purple identities, using system fonts, SF Symbols and native controls rather than copying the marketing illustrations. The existing signed-in Chrome WaniKani dashboard was subsequently inspected read-only: separate lesson/review cards, forecast, recent mistakes, Extra Study, level progress and Item Spread. Home follows that hierarchy. No live exercise was opened, progress changed or browser credential extracted. WKStats account views were not accessed.

| Reference | Implemented scope | Interpretation |
| --- | --- | --- |
| JLPT | Estimated cumulative N5–N1: 79, 245, 612, 979, 2,211 characters | Community estimates, not official/exhaustive exam lists. |
| Japanese school grades | Cumulative grades 1–6: 80, 240, 440, 642, 835, 1,026 | Current KANJIDIC2 school classifications. |
| Jōyō / Kyōiku | 2,136 / 1,026 | General-use / elementary-school sets. |
| Kanji Kentei | Official cumulative scopes for levels 10–2, including 4, 3 and pre-2 | Character coverage only; handwriting, readings, compounds and other exam skills are not assessed. |

Coverage matches only kanji subjects. Vocabulary or radicals containing the same character do not qualify. The full reference-set denominator includes characters outside the synced WaniKani catalog. Learning, not-started and outside-catalog counts remain distinct. Duplicate/canonically equivalent character forms count once, and thresholds describe current SRS milestones rather than permanent mastery. A partially synced iOS catalog is labelled “outside synced catalog,” not proof the service lacks a character.

[JLPT's official FAQ](https://www.jlpt.jp/e/faq/) explains that current kanji/vocabulary/grammar lists are not published. Consequently, this app does **not** offer a JLPT pass probability. An honest readiness estimate also requires external evidence of grammar, listening, vocabulary and reading comprehension. [Kanji Kentei's official 2020 allocation table](https://www.kanken.or.jp/kanken/outline/data/outline_degree_national_list20200217.pdf) supplies the intermediate subsets. Cumulative character totals are 80, 240, 440, 642, 835, 1,026, 1,339, 1,623, 1,951 and 2,136 for levels 10 through 2 (including pre-2). These totals describe scope, not passing readiness.

Dataset snapshots, licenses, transformations and the Swift refresh command are documented in [shared sources](../Shared/Sources/StudyCore/Resources/SOURCES.md), with attribution also visible inside the app. School grades use current KANJIDIC2 rather than the older 1,006-character school list found in some secondary datasets. The generator asserts current totals and preserves the earlier grade when Unicode canonical variants collide.

The iPhone, iPad and Mac app uses the same native SwiftData account-state pipeline, complete snapshot downloads and automatic uploading of confirmed eligible local work. Each device retains its own local outbox; the devices do not share an upload queue. Pending uploads suppress affected forecasts, and attempted or uncertain work requires reconciliation rather than automatic replay. When a user archives an uncertain native review/lesson answer, its old assignment is invalidated and the dashboard asks for a complete refresh instead of plotting incomplete progress or a false zero-due schedule. That state survives restart and failed refresh. Archival is a local choice, not evidence of a successful answer; archived payloads must not be counted as confirmed results or used as remote review history for calibration.

Pending reviews are not counted as confirmed SRS progress. The live snapshot includes transient
outbox subject IDs so curriculum charts show “Awaiting sync” separately from “Not started.” These
IDs are rebuilt from SwiftData on reads/refresh and are not part of the saved snapshot payload.
The SRS chart reports how many subjects are withheld until their reviews synchronize.

## Local clock updates

While Statistics is visible, SwiftUI's minute timeline recomputes the existing metrics using
its current date. Due counts move from future to overdue and seven-day buckets advance at
local midnight even without a download. This changes derived presentation only: it does not
fetch, submit reviews, rewrite the cached snapshot or advance the displayed snapshot timestamp.
Assignment/status changes still come from the normal WaniKani synchronization path. Counts
can lag the exact due instant by up to one minute while the screen remains open.
