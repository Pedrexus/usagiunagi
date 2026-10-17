import Foundation

public enum CurriculumSystem: String, CaseIterable, Identifiable, Sendable {
    case jlpt = "JLPT", school = "School grades", kanken = "Kanji Kentei", joyo = "Jōyō & Kyōiku"
    public var id: String { rawValue }
    public var explanation: String {
        switch self {
        case .jlpt: "Estimated kanji lists, including easier levels. This measures kanji coverage, not grammar, listening, vocabulary or exam readiness."
        case .school: "Cumulative Japanese school-grade kanji. Grade 6 includes all 1,026 elementary kanji."
        case .kanken: "Kanji scope for levels 10–5 and 2. Handwriting and other exam skills are not assessed. Levels 4, 3 and pre-2 need separately verified lists."
        case .joyo: "Elementary-school and everyday-use character sets. These describe kanji scope, not test scores."
        }
    }
}

public struct Curriculum: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let characters: Set<String>
}

public struct CurriculumLibrary: Decodable, Sendable {
    public struct Entry: Decodable, Sendable { public let grade: Int?; public let jlpt: Int? }
    public let version: Int
    public let kanjidicDate: String
    public let jlptRevision: String
    public let entries: [String: Entry]
    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "curricula", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func curricula(for system: CurriculumSystem) -> [Curriculum] {
        func make(_ id: String, _ title: String, _ includes: (Entry) -> Bool) -> Curriculum {
            Curriculum(id: id, title: title, characters: Set(entries.filter { includes($0.value) }.keys))
        }
        switch system {
        case .jlpt:
            return (1...5).reversed().map { n in make("N\(n)", "N\(n)") { ($0.jlpt ?? 0) >= n } }
        case .school:
            return (1...6).map { g in make("grade\(g)", "Grade \(g)") { (1...g).contains($0.grade ?? 0) } }
        case .kanken:
            return (1...6).map { g in make("kanken\(11-g)", "Level \(11-g)") { (1...g).contains($0.grade ?? 0) } } +
                [make("kanken2", "Level 2") { (1...6).contains($0.grade ?? 0) || $0.grade == 8 }]
        case .joyo:
            return [make("joyo", "Jōyō") { (1...6).contains($0.grade ?? 0) || $0.grade == 8 },
                    make("kyōiku", "Kyōiku") { (1...6).contains($0.grade ?? 0) }]
        }
    }
}

public struct CurriculumCoverage: Identifiable, Sendable {
    public let curriculum: Curriculum
    public let reached: Int
    public let learning: Int
    public let notStarted: Int
    public let outsideCatalog: Int
    public let remaining: [String]
    public var id: String { curriculum.id }
    public var total: Int { curriculum.characters.count }
    public var fraction: Double { total > 0 ? Double(reached) / Double(total) : 0 }

    public init(curriculum: Curriculum, subjects: [StudySubject], assignments: [StudyAssignment], threshold: Int = 5) {
        self.curriculum = curriculum
        let stages = Dictionary(assignments.map { ($0.subjectID, $0.srsStageNumber) }, uniquingKeysWith: max)
        var byCharacter = [String: Int]()
        for subject in subjects where subject.kind == .kanji {
            byCharacter[subject.characters] = max(byCharacter[subject.characters] ?? 0, stages[subject.id] ?? 0)
        }
        var reached = 0, learning = 0, notStarted = 0, outside = 0
        var remaining = [String]()
        for character in curriculum.characters {
            guard let stage = byCharacter[character] else { outside += 1; remaining.append(character); continue }
            if stage >= threshold { reached += 1 }
            else { remaining.append(character); if stage > 0 { learning += 1 } else { notStarted += 1 } }
        }
        self.reached = reached; self.learning = learning; self.notStarted = notStarted
        outsideCatalog = outside; self.remaining = remaining.sorted()
    }
}
