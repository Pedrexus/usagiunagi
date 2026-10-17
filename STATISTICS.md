# Statistics: sources, definitions and limits

Researched 2026-10-17. The first implementation uses existing synced WaniKani records; it does not upload account data to another service or change review scheduling.

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
| Next-level scenario | Current level unlock time + those two durations | Requires a known active level, no pending uploads/vacation, level below 60 and current elapsed time below the lower duration. Otherwise no date is shown. Does not model critical-path kanji or level-specific minimum times. |
| Focus next | Active, visible items with at least 5 answers and 2 errors on a side; use the worse eligible side | Priority score is `(errors + 1) / (answers + 2) / sqrt(currentCorrectStreak + 1)`. Zero streak is valid. Radicals have no reading side. This is a heuristic, not an estimated failure probability. |

The screen shows counts and relevant assumptions. Focus rows open existing subject details. Sample-data mode is visibly labelled and uses synthetic history; it must not be presented as the user's actual performance.

## Making forecasts more credible later

Keep exact schedules separate from conditional forecasts. Collect consented local review-event history with timestamps, result, stage and lesson choices before claiming recent trends or fitting a model. A local history will be incomplete for reviews performed on other clients unless the API supplies them.

Backtest candidate forecasts chronologically against held-out future periods. Compare against a simple median-pace baseline. Report absolute date/workload error, sample size, and interval coverage; test resets, long breaks, fast levels and habit changes separately. Do not label a percentile band “80% confidence” without calibration. A useful next iteration would simulate known SRS intervals and critical-path kanji under explicit lesson/review scenarios, then compare those scenarios with observed outcomes.

## Validation

`StudyStatisticsTest` covers empty data, weighted accuracy, hidden subjects, duplicate assignments, lesson/burned exclusion, missing due dates, minimum focus evidence, zero/recovery streaks, median/quartile arithmetic, vacation/overdue scenarios, resets and duplicate level records. Existing grading/kana tests remain enabled.

Simulator sample-data checks do not establish real-account sync correctness, prediction calibration or physical-device input behavior. No such claims are made.
