# Reusable Swift helpers

## Owner-authorized dataclass package

The owner subsequently requested our own `dataclass` implementation. It now lives in the projects workspace at `packages/dataclass`, separate from Patos and this app. Its `Dataclass` macro/runtime generates validated struct/final-class initialization, strict/open native Codable and explicit revalidation. `DataclassSwiftData` adds `ModelContext.saveValidated()` without replacing SwiftData storage. Mainboard owns its native build, formatting and disposable CLI showcase tasks.

Swift 6.4 compiler evidence found an important composition limit: Apple's `@Model` cannot see a neighboring member macro's initializer, even in the reverse order or with all property defaults. The package therefore documents one private, uncallable source initializer taking `Never`; generated memberwise construction remains validated. It preserves native backing storage and identities. Explicit saves cannot validate autosave, batch operations, CloudKit imports or materialization automatically. MainActor classes need correctly isolated conformances, not suppressed diagnostics.

The standalone manual showcase builds and demonstrates aggregate validation, missing-only defaults, strict/open payload handling, a corrected native-store reopen with stable UUID, and a background `@ModelActor` save. App integration, historical decoder/schema adoption and automated tests remain open. Tests stay at the end under the owner's latest instruction. No `Dataclass` dependency or frozen model rewrite has been introduced into this app. Read the package README and STATUS before choosing a small nonpersistent pilot; existing native synthesis is still preferred where sufficient.

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
