import Testing
import StudyCore

@Test(arguments: [
    ("", "", 0), ("", "abc", 3), ("kitten", "sitting", 3),
    ("bunny", "bnuny", 1), ("ab", "ba", 1), ("CA", "ABC", 3),
    ("aab", "aba", 1), ("same", "same", 0),
    ("", "😀", 2), ("😀", "😁", 1), ("😀a", "a😀", 2),
    ("é", "e\u{301}", 2), ("が", "か\u{3099}", 2), ("鰻", "𠮷", 2)
])
func legacyDistanceCases(_ a: String, _ b: String, _ expected: Int) {
    #expect(AnswerDistance.between(a, b) == expected)
    #expect(AnswerDistance.between(b, a) == expected)
}

@Test func distanceHandlesLongInputsWithoutAFullMatrix() {
    let prefix = String(repeating: "a", count: 2000)
    #expect(AnswerDistance.between(prefix + "bc", prefix + "cb") == 1)
}
