# Mainboard Apple reporting checkpoint

## Deferred Apple and Swift regression gate

The final test stage ran the six existing Apple/Swift rule modules through Mainboard's isolated gate: `test_swift_analysis`, `test_swift_style`, `test_swift_platform`, `test_swift_persistence`, `test_apple` and `test_apple_fonts`. All 228 cases pass (82.91 seconds); the native isolation canary passes. Two existing Pathspec deprecation warnings remain. Evidence is `/private/tmp/usagi-mainboard-apple-gate-final/{target.json,target.xml,target.log}`.

The initial run passed 225 cases and failed three because the Apple result fake handled only test results, while execution now also retains build diagnostics. The fake now models both read commands. The existing three native/test-verdict combinations retain their exit assertions and also verify both report files refer to the same bundle and preserve the original build summary/test verdict. A new assertion initially compared the different `.build`/`.tests` filename stems; it was corrected to compare the reported bundle identities before the passing rerun. Production executor behavior was not weakened. Mainboard commit `1d6b2d7` contains only this test update and formatter ordering; its production sources remain at `ce366957`.

This targeted gate does not establish the whole Mainboard suite, full typing/lint, hosted Actions or app usability. The older production checkpoint below remains historical; its statement that P0c was unapplied has been superseded by the owner's approval and the [generation opener](2026-10-20-native-store-opening.md).

Mainboard commit: `ce36695787001398c206b5f7e0250447e3d13ee7`, branch `codex/apple-development`, based on `a2e0e20933b5fda48e4b7402b4f1e6d88d8872b3`. App source remains at `ebd706a9` plus the three untouched, off-target owner edits. This checkpoint changes app workflow/docs only. No tests, GUI launches, real exercises, PR, push or distribution occurred.

## Reusable production work

The Apple executor attempts build diagnostics after every native execution with a result bundle, including nonzero exits. Test actions independently attempt their test report. Each readable report is retained as a JSON sidecar using the existing typed document shape and Mainboard's atomic generated-file writer under the results-directory lock. Existing report files are never intentionally replaced. Missing/unreadable reports are explicit errors; no older successful bundle is substituted. Native nonzero exit codes survive report capture; native zero still requires successful report verdicts. Resolve actions have no result bundle and retain their existing behavior.

`analyze swift-compare BASELINE CURRENT --json` reads two saved Swift inventories without invoking Xcode or rereading source. It retains artifact hashes, both parser/toolchain identities, changed rule IDs, category totals, byte changes and separate reclassifications. It rejects duplicate/out-of-scope/aliased paths, invalid hashes/languages/counts, mismatched totals, conflicting measurements for repeated hashes and contradictory parser coverage. Same bytes at a new path remain an addition/removal; no semantic rename or equivalent behavior is inferred. Root paths may differ across machines; relative scopes must match.

The comparator reuses inventory models and the same totals calculation as inventory generation. No app-local script, new dependency, persisted app-model change or generic scripting wrapper was introduced. Future arbitrary Swift transformations still need syntax/semantic analysis and compiler-aware verification; these report tools are not an autofix implementation.

## Operational evidence

The new executor performed an unsigned Debug build of the unchanged iOS/watch/widget graph through Mainboard, with Xcode27 selected per invocation. Native exit: 0. Exact bundle: `.build/Results/build-21d1a5f4032c4aed83cafbbf80db921e.xcresult`. It automatically retained `.build/Results/build-21d1a5f4032c4aed83cafbbf80db921e.build.json`; inspected fields show the exact matching bundle, `build_successful=true`, zero errors and zero warnings in the incremental scope. Its SHA256 is `59b43ca46ccca9a27bc1420302f96177f02c3a8c98f94a48b5735742d1c221e7`. This proves the real successful-build/report path only, not failure or test-action behavior.

The real saved-inventory comparison reports one added source, five modified sources, zero removals/reclassifications and 257 same-path byte matches. It reports production 20,760 → 20,487 physical lines, tests 23,717 → 23,717 and tooling 282 → 282. The test/tooling source paths are absent from the added/removed/modified lists; no inference of behavior preservation follows. Counts include all classified sources, including the three off-target owner files.

| Artifact | SHA256 |
| --- | --- |
| `.build/Reports/WatchSwiftUIInventory.json` | `c2cfe2aa98b7ef736f1849e391a09fd0d766c4473e03007108976f2b8e209cd9` |
| `.build/Reports/WidgetKitInventory.json` | `ec64674248ccbbdb09b65d6fa4ee89dc71c2f8325b15a325b67b69c649b02c42` |
| `.build/Reports/WidgetKitSourceComparison.json` | `9e31b1ddef9614a46203add74dd2afc77bd01c63dae9630d99fb7b2857d512cd` |

Mainboard's frozen production sources:

```text
9553a65267255d88f9874fb5755a9804ce2208b1c81978fcaedb727db6af5a99  src/mainboard/apple.py
3fcb73431e92abaf4a3d21ec90fa990beea959d3f598565aba641909d77b9ccc  src/mainboard/cli.py
a85d90a3884194ffde6eb25b10ae694d156085cb9af88ee091d9b41224e56556  src/mainboard/analysis/commands/swift_inventory.py
```

Source review corrected two internally contradictory-report cases: repeated SHA256 values with different byte/line counts, and parsed flags incompatible with status/gaps/toolchain. The final real comparison was rerun after those changes. No malformed or negative fixture was executed. The successful Apple executor sources did not change after its real build. Formatting rewrote only the changed production code.

## Pending acceptance

Formal regressions remain at the owner's final test stage: native nonzero/timeout retention, malformed/missing/build-before-test evidence, independent report failures, zero-native-but-unsuccessful verdicts, report collision/atomic publication, CLI invocation; inventory duplicates/paths/counts/scope/reclassification, repeated digest measurement contradictions, parser status/gaps/toolchain coherence, rule changes and no-Xcode operation. Full typing/lint and the previously deferred parser/rule regressions remain open. Review and one real successful operation do not replace them.

Sidecars describe the native result bundle; saved source observations neither authenticate their origin nor establish which bytes Xcode read. No new compiler-input attestation is claimed. Existing workflow uploads already include Results sidecars; all three Mainboard references now pin this local commit. Publishing that commit requires separate authorization before hosted Actions can fetch it. No hosted run is claimed.

The main-app P0c store-opening patch remains unapplied after automatic approval-review rejection. This tooling work does not alter it or bypass its pending approval. Finish production changes, then compare original Tsurukame usability, then port/run tests as ordered.
