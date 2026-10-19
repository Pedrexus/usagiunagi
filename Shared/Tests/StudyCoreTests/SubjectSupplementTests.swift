import CryptoKit
import Foundation
import Testing

@testable import StudyCore

struct SubjectSupplementTests {
  @Test func everyOriginalStudySupplementSurvivesConsolidation() throws {
    let catalog = try StudySubjectSupplements.bundled.get()
    #expect(catalog.mnemonics.count == 79)
    #expect(catalog.similar.count == 2380)
    for (values, expected) in [
      (catalog.mnemonics, "293dec08b84ee2b659aeffa9630635881c65deac8cd2a1dec6300b46349f49cd"),
      (catalog.similar, "0333448af560175d4e7541267b3348a2a7c3550d2506618d9fb7026d4ca53711"),
    ] {
      let canonical = values.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        .map { "\($0):\(values[$0]!)\n" }.joined()
      let digest = SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }.joined()
      #expect(digest == expected)
    }
    #expect(catalog.deprecatedMnemonic(subjectID: 102)?.contains("Two Face") == true)
    #expect(catalog.similarKanji(to: "一") == "互下両土且正本末未士丁七二十")
    #expect(catalog.deprecatedMnemonic(subjectID: -1) == nil)
    #expect(catalog.similarKanji(to: "") == nil)
  }
}
