import Foundation

extension WaniKaniClient {
  private struct SubjectData: Decodable, Sendable {
    struct Meaning: Decodable, Sendable {
      let meaning: String
      let primary: Bool
      let acceptedAnswer: Bool
    }
    struct Auxiliary: Decodable, Sendable {
      let meaning: String
      let type: String
    }
    struct Reading: Decodable, Sendable {
      let reading: String
      let primary: Bool
      let acceptedAnswer: Bool
      let type: String?
    }
    struct Image: Decodable, Sendable {
      struct Metadata: Decodable, Sendable { let inlineStyles: Bool? }
      let url: String
      let contentType: String
      let metadata: Metadata
    }
    struct Audio: Decodable, Sendable {
      struct Metadata: Decodable, Sendable { let voiceActorId: Int64? }
      let url: String
      let contentType: String
      let metadata: Metadata
    }
    struct Sentence: Decodable, Sendable {
      let ja: String
      let en: String
    }
    let characters: String?
    let meanings: [Meaning]
    let auxiliaryMeanings: [Auxiliary]
    let readings: [Reading]?
    let level: Int
    let slug: String
    let documentUrl: String
    let hiddenAt: String?
    let lessonPosition: Int
    let spacedRepetitionSystemId: Int64
    let meaningMnemonic: String
    let meaningHint: String?
    let readingMnemonic: String?
    let readingHint: String?
    let amalgamationSubjectIds: [Int64]?
    let componentSubjectIds: [Int64]?
    let visuallySimilarSubjectIds: [Int64]?
    let characterImages: [Image]?
    let pronunciationAudios: [Audio]?
    let contextSentences: [Sentence]?
    let partsOfSpeech: [String]?
  }
  private struct StatisticData: Decodable, Sendable {
    let subjectId: Int64
    let subjectType: String
    let createdAt: String
    let meaningCorrect: Int
    let meaningIncorrect: Int
    let meaningCurrentStreak: Int
    let meaningMaxStreak: Int
    let readingCorrect: Int
    let readingIncorrect: Int
    let readingCurrentStreak: Int
    let readingMaxStreak: Int
    let percentageCorrect: Int
    let hidden: Bool
  }
  private struct LevelData: Decodable, Sendable {
    let level: Int
    let createdAt: String
    let unlockedAt: String?
    let startedAt: String?
    let passedAt: String?
    let completedAt: String?
    let abandonedAt: String?
  }
  private struct SystemData: Decodable, Sendable {
    struct Stage: Decodable, Sendable {
      let position: Int
      let interval: Double?
      let intervalUnit: String?
      func value() throws(APIError) -> StudySRSSystem.Stage {
        guard let interval else {
          guard intervalUnit == nil else { throw .invalidResponse }
          return .init(position: position, interval: nil)
        }
        let multiplier: Double
        switch intervalUnit {
        case "milliseconds": multiplier = 0.001
        case "seconds": multiplier = 1
        case "minutes": multiplier = 60
        case "hours": multiplier = 3600
        case "days": multiplier = 86400
        case "weeks": multiplier = 604800
        default: throw .invalidResponse
        }
        return .init(position: position, interval: interval * multiplier)
      }
    }
    let name: String
    let unlockingStagePosition: Int
    let startingStagePosition: Int
    let passingStagePosition: Int
    let burningStagePosition: Int
    let stages: [Stage]
  }
  private func system(_ resource: Resource<SystemData>) throws -> StudySRSSystem {
    let d = resource.data
    let value = try StudySRSSystem(
      id: resourceID(resource, kind: "spaced_repetition_system"), name: d.name,
      unlockingStage: d.unlockingStagePosition, startingStage: d.startingStagePosition,
      passingStage: d.passingStagePosition, burningStage: d.burningStagePosition,
      stages: d.stages.map { try $0.value() })
    try value.validate()
    return value
  }

  private struct VoiceData: Decodable, Sendable {
    let name: String
    let description: String
    let gender: String
  }

  /// Includes hidden resources so a complete refresh can remove them from study queues.
  /// It does not mutate a store or advance a sync cursor after a partial download.
  @concurrent public func download(token: String) async throws -> StudyDownload {
    let user = try await accountData(token: token)
    guard let profile = try accountProfile(user) else { throw APIError.invalidResponse }

    async let subjectPages: [Resource<SubjectData>] = pages("subjects", token: token)
    async let assignmentPages: [Resource<AssignmentData>] = pages("assignments", token: token)
    async let materialPages: [Resource<MaterialData>] = pages("study_materials", token: token)
    async let statisticPages: [Resource<StatisticData>] = pages("review_statistics", token: token)
    async let levelPages: [Resource<LevelData>] = pages("level_progressions", token: token)
    async let voicePages: [Resource<VoiceData>] = pages("voice_actors", token: token)
    async let systemPages: [Resource<SystemData>] = pages("spaced_repetition_systems", token: token)
    let (subjects, assignments, materials, statistics, levels, voices, systems) = try await (
      subjectPages, assignmentPages, materialPages, statisticPages, levelPages, voicePages,
      systemPages
    )
    try Task.checkCancellation()
    let catalog = try subjects.map(subject)
    try uniqueIDs(catalog.map(\.id))
    let fullSystems = try systems.map(system)
    try uniqueIDs(fullSystems.map(\.id))
    let systemIDs = Set(fullSystems.map(\.id))
    guard catalog.allSatisfy({ $0.spacedRepetitionSystemID.map(systemIDs.contains) == true }) else {
      throw APIError.invalidResponse
    }
    let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    let fullAssignments = try assignments.map { resource in
      var value = try assignment(resource, subjectID: resource.data.subjectId)
      guard let subject = byID[value.subjectID], subject.kind == value.kind,
        (subject.isKanaOnlyVocabulary == true) == value.isKanaOnlyVocabulary
      else { throw APIError.invalidResponse }
      // The assignment API has no level: its subject is the authority.
      value.level = subject.level
      value.hidden = resource.data.hidden == true || subject.hiddenAt != nil
      return value
    }
    let fullMaterials = try materials.map { try material($0, subjectID: $0.data.subjectId) }
    let fullStatistics = try statistics.map(statistic)
    let fullLevels = try levels.map(level)
    let fullVoices = try voices.map(voice)
    for ids in [
      fullAssignments.map(\.id), fullAssignments.map(\.subjectID), fullMaterials.map(\.id),
      fullMaterials.map { $0.value.subjectID }, fullStatistics.map(\.id),
      fullStatistics.map { $0.answers.subjectID }, fullLevels.map(\.id), fullVoices.map(\.id),
    ] { try uniqueIDs(ids) }
    return StudyDownload(
      accountID: user.id, profile: profile, subjects: catalog, assignments: fullAssignments,
      materials: fullMaterials, levels: fullLevels, statistics: fullStatistics, voices: fullVoices,
      systems: fullSystems)
  }

  private func uniqueIDs(_ ids: [Int64]) throws(APIError) {
    guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else {
      throw APIError.invalidResponse
    }
  }
  private func resourceID<T>(_ resource: Resource<T>, kind: String) throws(APIError) -> Int64 {
    guard resource.object == kind, let id = resource.id, id > 0 else {
      throw APIError.invalidResponse
    }
    return id
  }

  private func subject(_ resource: Resource<SubjectData>) throws -> CatalogSubject {
    guard let object = resource.object, let id = resource.id, id > 0 else {
      throw APIError.invalidResponse
    }
    let data = resource.data
    guard (1...60).contains(data.level), data.lessonPosition >= 0,
      data.spacedRepetitionSystemId > 0,
      !data.meanings.isEmpty
    else { throw APIError.invalidResponse }
    var value = CatalogSubject(id: id, kind: try kind(object))
    value.level = data.level
    value.slug = data.slug
    value.documentURL = data.documentUrl
    value.japanese = data.characters ?? ""
    value.hiddenAt = try data.hiddenAt.map(timestamp)
    value.lessonPosition = data.lessonPosition
    value.spacedRepetitionSystemID = data.spacedRepetitionSystemId
    value.isKanaOnlyVocabulary = object == "kana_vocabulary"
    // Preserve the legacy grader's primary/secondary interpretation of accepted_answer.
    value.meanings = data.meanings.map {
      .init($0.meaning, role: $0.primary ? .primary : .secondary)
    }
    value.meanings += try data.auxiliaryMeanings.map {
      guard ["whitelist", "blacklist"].contains($0.type) else { throw APIError.invalidResponse }
      return .init($0.meaning, role: $0.type == "blacklist" ? .blacklist : .auxiliaryWhitelist)
    }
    value.readings = try (data.readings ?? []).filter { $0.reading != "None" }.map { reading in
      let kind: CatalogSubject.Reading.Kind
      switch reading.type {
      case "onyomi": kind = .onyomi
      case "kunyomi": kind = .kunyomi
      case "nanori": kind = .nanori
      case nil: kind = .unknown
      default: throw APIError.invalidResponse
      }
      return .init(reading.reading, isPrimary: reading.primary, kind: kind)
    }
    value.meaningMnemonic = data.meaningMnemonic
    value.meaningHint = data.meaningHint ?? ""
    value.readingMnemonic = data.readingMnemonic ?? ""
    value.readingHint = data.readingHint ?? ""
    value.componentSubjectIDs = data.componentSubjectIds ?? []
    value.amalgamationSubjectIDs = data.amalgamationSubjectIds ?? []
    value.visuallySimilarKanjiIDs = data.visuallySimilarSubjectIds ?? []
    for ids in [
      value.componentSubjectIDs, value.amalgamationSubjectIDs, value.visuallySimilarKanjiIDs,
    ] { try uniqueIDs(ids) }
    if value.kind == .radical, value.japanese.isEmpty {
      guard
        let image = data.characterImages?.first(where: {
          $0.contentType == "image/svg+xml" && $0.metadata.inlineStyles == true
        })
      else {
        throw APIError.invalidResponse
      }
      value.characterImageURL = image.url
      value.hasCharacterImageFile = true
    }
    value.sentences = (data.contextSentences ?? []).map { .init(japanese: $0.ja, english: $0.en) }
    value.audio = (data.pronunciationAudios ?? []).filter { $0.contentType == "audio/mpeg" }.map {
      .init(url: $0.url, voiceActorID: $0.metadata.voiceActorId ?? 0)
    }
    value.partOfSpeechNames = data.partsOfSpeech
    value.partsOfSpeech = (data.partsOfSpeech ?? []).compactMap(Self.legacyPartOfSpeech)
    let supplements = try StudySubjectSupplements.bundled.get()
    value.deprecatedMnemonic = supplements.deprecatedMnemonic(subjectID: id) ?? ""
    value.visuallySimilarKanji = supplements.similarKanji(to: value.japanese) ?? ""
    return value
  }

  private func statistic(_ resource: Resource<StatisticData>) throws -> CatalogReviewStatistic {
    let id = try resourceID(resource, kind: "review_statistic")
    let d = resource.data
    guard d.subjectId > 0, (0...100).contains(d.percentageCorrect),
      [
        d.meaningCorrect, d.meaningIncorrect, d.meaningCurrentStreak, d.meaningMaxStreak,
        d.readingCorrect, d.readingIncorrect, d.readingCurrentStreak, d.readingMaxStreak,
      ].allSatisfy({ $0 >= 0 })
    else { throw APIError.invalidResponse }
    var value = CatalogReviewStatistic(
      id: id,
      answers: .init(
        subjectID: d.subjectId, type: try kind(d.subjectType),
        meaningCorrect: d.meaningCorrect, meaningIncorrect: d.meaningIncorrect,
        meaningCurrentStreak: d.meaningCurrentStreak,
        readingCorrect: d.readingCorrect, readingIncorrect: d.readingIncorrect,
        readingCurrentStreak: d.readingCurrentStreak, hidden: d.hidden))
    value.createdAt = try timestamp(d.createdAt)
    value.meaningMaxStreak = d.meaningMaxStreak
    value.readingMaxStreak = d.readingMaxStreak
    value.percentageCorrect = d.percentageCorrect
    return value
  }
  private func level(_ resource: Resource<LevelData>) throws -> CatalogLevelProgression {
    var value = CatalogLevelProgression(id: try resourceID(resource, kind: "level_progression"))
    let d = resource.data
    guard (1...60).contains(d.level) else { throw APIError.invalidResponse }
    value.level = d.level
    value.createdAt = try timestamp(d.createdAt)
    value.unlockedAt = try d.unlockedAt.map(timestamp)
    value.startedAt = try d.startedAt.map(timestamp)
    value.passedAt = try d.passedAt.map(timestamp)
    value.completedAt = try d.completedAt.map(timestamp)
    value.abandonedAt = try d.abandonedAt.map(timestamp)
    return value
  }
  private func voice(_ resource: Resource<VoiceData>) throws -> StudyVoiceActor {
    var value = StudyVoiceActor(id: try resourceID(resource, kind: "voice_actor"))
    value.name = resource.data.name
    value.description = resource.data.description
    value.gender = resource.data.gender == "male" ? 1 : resource.data.gender == "female" ? 2 : 0
    return value
  }

  private static func legacyPartOfSpeech(_ name: String) -> Int? {
    let names = [
      "noun", "numeral", "intransitive_verb", "ichidan_verb", "transitive_verb", "no_adjective",
      "godan_verb", "na_adjective", "i_adjective", "suffix", "adverb", "suru_verb", "prefix",
      "proper_noun",
      "expression", "adjective", "interjection", "counter", "pronoun", "conjunction",
    ]
    let normalized = name.replacingOccurrences(of: " ", with: "_")
      .replacingOccurrences(of: "の_adjective", with: "no_adjective").replacingOccurrences(
        of: "な_adjective", with: "na_adjective"
      )
      .replacingOccurrences(of: "い_adjective", with: "i_adjective").replacingOccurrences(
        of: "する_verb", with: "suru_verb")
    return names.firstIndex(of: normalized).map { $0 + 1 }
  }
}
