# Reusable Swift helpers

## Owner-authorized dataclass package

### Latest initializer, validation and ownership requests

The October 21 source follow-up adds a nonthrowing `@Memberwise` constructor-only path, retaining native Codable synthesis, and default-backed typed-rule inference for non-Codable `@Dataclass` fields. The compiler checks `Rule.Value` against the Swift-inferred stored default; explicit types remain required for generated Codable to keep optional/null behavior explicit. The package's existing manual CLI compiles the exact two-field shape of the nonpersistent `PendingUploadKey` as a pilot. It saves three initializer lines, while the SwiftSyntax checkout alone occupies 12 MiB. The app deliberately retains native public constructors and zero Shared dependencies: an unpublished macro package, a machine-local relative dependency or duplicated vendored source would add more maintenance than the measured saving. The library source and final Mac tests pass; external package publication/adoption remain separate.

The current ownership audit retains weak captures where the owner stores a task, callback, delegate or observation token. Automatic/mistake sync and notification workers are long-lived streams cancelled on teardown/account changes; promoting self only inside each iteration avoids holding the service through the next suspension. Speech capture/reporting and completion deadlines use recording identities and cancellation. Audio/player monitoring, download callbacks and font transfers must not keep their owners alive indefinitely. Store-stream termination must not retain the store through its own continuation. Japanese input configuration uses weak fields because responder changes are deferred beyond view updates and teardown. Watch connectivity callbacks avoid a helper/handler or observation cycle while the helper strongly retains the weak system delegate. Finite task completion does not justify removing those lifetime boundaries. No blanket weak-reference ban or unchecked ownership annotation is introduced; final cancellation/deallocation regressions remain required.

The owner asks for a deeper modern-Swift review of the macro composition workaround, inferred/domain validation, simpler models and other forwarding-only constructors. This remains an active implementation workstream after portable preferences; it is not closed by the existing initial package. Preserve the native-first rule and do not introduce a local-only app package path that cannot be restored from the standalone GitHub checkout. The general package currently lives outside this repository and has not been published.

The private `Never` initializer is a workaround for **our macro composed with `@Model`**, not a general SwiftData requirement. Ordinary SwiftData models can use ordinary initializers. The installed Xcode 27/Swift 6.4 interface still exposes `@Model` as a member/member-attribute/extension macro. Its `@Attribute` signature has schema options, original name and hash modifier, not arbitrary scalar range/nonblank rules. `ModelConfiguration.validate()` validates a store configuration, not each row. `ModelContext` provides save/transaction, autosave and notifications; [willSave/didSave are notifications](https://developer.apple.com/documentation/swiftdata/modelcontext), not a throwing validation interceptor. Keep explicit validation before local saves and when applying imported data. Native constraints can handle the constraints they actually express; they cannot infer domain-specific valid values or authorize schema changes.

The parser/expansion follow-up now implements typed `ValidationRule.Value` inference and a constructor-only path for nonvalidating DTOs, as scoped above. Do not add `try` throughout the app merely to remove assignment-only initializers, infer business rules from property names, weaken decoding failures into defaults, change persistent identities, or guess arbitrary expression types from syntax. The earlier thirty native initializer removals remain valid; broader adoption still needs actual candidates, reproducible consumption and measured benefit.

The preferences implementation also resolves a concrete ownership issue: services now publish typed edits to `StudyICloudPreferences`, while SwiftUI observes its revision to reload services. The iCloud owner has no callback back to its publishers, eliminating eight provisional weak captures. This does not justify banning weak references. [Swift ARC](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/) retains closure-cycle rules, while [Task lifetime guidance](https://developer.apple.com/documentation/swift/task#Task-closure-lifetime) explains that completed task closures release captures. Finite operations, long-lived event streams and recurring workers require different lifetime reasoning. Existing weak event-stream captures remain until their cancellation/ownership contracts are established.

The owner subsequently requested our own `dataclass` implementation. It now lives in the projects workspace at `packages/dataclass`, separate from Patos and this app. Its `Dataclass` macro/runtime generates validated struct/final-class initialization, strict/open native Codable and explicit revalidation. `DataclassSwiftData` adds `ModelContext.saveValidated()` without replacing SwiftData storage. Mainboard owns its native build, formatting and disposable CLI showcase tasks.

Swift 6.4 compiler evidence found an important composition limit: Apple's `@Model` cannot see a neighboring member macro's initializer, even in the reverse order or with all property defaults. The package therefore documents one private, uncallable source initializer taking `Never`; generated memberwise construction remains validated. It preserves native backing storage and identities. Explicit saves cannot validate autosave, batch operations, CloudKit imports or materialization automatically. MainActor classes need correctly isolated conformances, not suppressed diagnostics.

The standalone showcase demonstrates aggregate validation, missing-only defaults, strict/open payload handling, a corrected native-store reopen with stable UUID, and a background `@ModelActor` save. The subsequent final test phase passes 12 runtime/persistence functions and four macro functions, including five rejected-declaration cases; relationships, deletion, mutable validation and disk reopening are covered. Projects commit `e55818c5a` records those tests and Mainboard tasks. No `Dataclass` dependency or frozen model rewrite is introduced into this app. The measured nonpersistent pilot and decision above retain explicit native construction in the app; historical decoder/schema adoption remains conditional on a future justified schema change.

The earlier alternatives and sketch below retain their research context. The new owner request supersedes the recommendation to defer a package until another consumer appears; it does not authorize changing frozen study schemas or claim that the entire app modernization is complete.

The owner wants the same small, reusable patterns that Patos supplies in Python. The useful Swift equivalents are native synthesis, narrowly applied compile-time macros, and typed validation shared by construction and decoding. This does not require a new application base class, ORM or runtime dependency-injection framework.

## Existing packages before another compiler plugin

| Need | Candidate | Adoption boundary |
| --- | --- | --- |
| Internal struct initialization | Native Swift synthesis | Already used; thirty redundant initializers removed |
| Public struct memberwise initialization | [MemberwiseInit](https://github.com/gohanlon/swift-memberwise-init-macro) | First candidate for forwarding-only public DTOs; preserve parameter labels, defaults, closure escaping and access diagnostics |
| Class memberwise initialization | The same package, with experimental class support | Inspect expansions and compile concrete cases first; inheritance, service construction and lifecycle ownership still need explicit decisions |
| Codable field names and missing-value defaults | [MetaCodable](https://github.com/SwiftyLab/MetaCodable) | Consider at external API boundaries after a measured boilerplate inventory; use missing-only defaults, not failure-masking defaults |
| Repeated domain validation | A small typed `Validated<Rule>` value in a future Patos Swift product | Define a domain rule once; call it from ordinary and Codable initialization. Keep the stored value immutable and provide no public unchecked initializer |
| SwiftData model construction | Retain explicit initializers initially | An initializer macro must compose with `@Model`/`@Attribute` and preserve generated metadata, defaults, identities and historical decoder behavior before adoption |

MemberwiseInit's latest published release was verified as 0.6.0 on October 21, 2026. Its manifest accepts SwiftSyntax through the 604 series. It is a Swift package/compiler macro, so CocoaPods is unnecessary. Its documented safety diagnostics refuse accidental exposure of private properties; the unchecked variant is outside the proposed scope. Macros generate explicit source at compile time rather than bypassing access control or inventing validation rules. Macro/type inference has limits: MetaCodable, for example, documents cases requiring explicit property types.

The small public-data pilot would look like this:

```swift
import MemberwiseInit

@MemberwiseInit(.public)
public struct ReviewTotals: Sendable {
  public let correct: Int
  public let incorrect: Int
}
```

This example is a proposed pilot, not an installed dependency or a compiled application change. The next implementation should select actual nonpersistent forwarding initializers, record their line savings and expanded interfaces, and check build/dependency cost before making the macro a shared default. Do not replace native synthesis that already works. Keep the current SwiftLint rule, adjusting it only if a real macro expansion produces a false positive.

## Patos Swift shape

The inspected Patos bases distinguish immutable and mutable values and strict app-owned payloads from open third-party responses. Preserve that distinction in Swift: structs/let for values, Codable's normal unknown-key tolerance for evolving WaniKani responses, strict versioned parsing where the app owns a recoverable wire format, and explicit domain validation. Do not apply Pydantic-style coercion to subject IDs, account identities, answer counters or malformed stored data.

A reusable validation core can be small:

```swift
public protocol ValidationRule {
  associatedtype Value: Codable & Sendable
  static func validate(_ value: Value) throws
}

public struct Validated<Rule: ValidationRule>: Codable, Sendable {
  public let value: Rule.Value

  public init(_ value: Rule.Value) throws {
    try Rule.validate(value)
    self.value = value
  }

  public init(from decoder: any Decoder) throws {
    try self.init(Rule.Value(from: decoder))
  }

  public func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
  }
}
```

This is a design sketch, not a new runtime model hierarchy. Conditional Equatable/Hashable conformances can be synthesized when the rule's Value supports them. Add it to a real Swift package when at least two concrete consumers remove repeated validation; do not create an unused framework solely for the sketch. Patos currently has unrelated owner edits, which remain untouched.

The sketch and two concrete rules (quarter-step font sizes and nonempty text) type-check successfully with the installed Swift 6.4 compiler in Swift 6 mode and warnings-as-errors. This is a bounded manual compiler check of `/private/tmp/usagi-validated-value-sketch.swift`, not execution of construction/decoding tests, an app integration or macro-composition proof. Receipt: `.build/Results/SwiftValidationTypecheck.log`, exit 0 with no diagnostics. Automated behavior tests remain deferred under the owner's latest sequence.

Keep persistence identities stable and validation errors explicit. Neither a macro nor a wrapper can decide whether an ID is server-owned, locally generated or immutable after insertion. Codable defaults must distinguish missing input from invalid input. Frozen study schemas and nested decoders are outside a mechanical initializer replacement.

## Sequence and current status

1. Finish settings ownership against the documented WaniKani preferences and extend app-only private sync.
2. Inventory forwarding public constructors and duplicate validation; choose the smallest real macro/helper pilot.
3. Review source, macro expansions, generated interfaces, manual build behavior and dependency cost.
4. Run automated tests only at the end, after implementation and permitted manual checks, following the owner's latest instruction.

No macro dependency, CocoaPods setup, Patos source change or SwiftData constructor rewrite is introduced by this research. Existing native synthesis remains active. This decision prevents a new general framework from getting ahead of actual application needs.
