// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

public struct StudySessionOptions: Codable, Equatable, Sendable {
  public enum AnkiMode: String, Codable, CaseIterable, Sendable {
    case off, meaning, reading, both
    public func includes(_ kind: StudyQuestionKind) -> Bool {
      self == .both || (self == .meaning && kind == .meaning)
        || (self == .reading && kind == .reading)
    }
  }
  public var ankiMode = AnkiMode.off
  public var batchSize = 5
  public var groupMeaningReading = false
  public var combinedAnki = false
  public var meaningFirst = true
  public var incorrectAnswerDelay = 5
  public var skipKanjiReadings = false
  public var minimizePenalty = false
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case ankiMode, batchSize, groupMeaningReading, combinedAnki, meaningFirst
    case incorrectAnswerDelay, skipKanjiReadings, minimizePenalty
  }
  public init(from decoder: any Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    batchSize = try values.decodeIfPresent(Int.self, forKey: .batchSize) ?? batchSize
    groupMeaningReading =
      try values.decodeIfPresent(Bool.self, forKey: .groupMeaningReading) ?? groupMeaningReading
    combinedAnki = try values.decodeIfPresent(Bool.self, forKey: .combinedAnki) ?? combinedAnki
    ankiMode =
      try values.decodeIfPresent(AnkiMode.self, forKey: .ankiMode) ?? (combinedAnki ? .both : .off)
    meaningFirst = try values.decodeIfPresent(Bool.self, forKey: .meaningFirst) ?? meaningFirst
    incorrectAnswerDelay =
      try values.decodeIfPresent(Int.self, forKey: .incorrectAnswerDelay) ?? incorrectAnswerDelay
    skipKanjiReadings =
      try values.decodeIfPresent(Bool.self, forKey: .skipKanjiReadings) ?? skipKanjiReadings
    minimizePenalty =
      try values.decodeIfPresent(Bool.self, forKey: .minimizePenalty) ?? minimizePenalty
  }
}

public struct StudyAnswerAttempt: Codable, Equatable, Sendable {
  public fileprivate(set) var firstAnswerWrong: Bool?
  public fileprivate(set) var wrongCount = 0
  public fileprivate(set) var answered = false
  public var hasAttempts: Bool { firstAnswerWrong != nil || answered }
  public init() {}
}

/// Stable entry IDs distinguish practice cards even when their WaniKani subject IDs are all zero.
public struct StudySessionItem: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let subjectID: Int64
  public let assignmentID: Int64
  public let srsStage: Int
  public let availableAt: Int64
  public let isLesson: Bool
  public let isKanji: Bool
  public let hasMeaning: Bool
  public let hasReading: Bool
  public fileprivate(set) var meaning = StudyAnswerAttempt()
  public fileprivate(set) var reading = StudyAnswerAttempt()
  public fileprivate(set) var returnDelay = 0
  public fileprivate(set) var createdAt: Int64?
  public var hasAttempts: Bool { meaning.hasAttempts || reading.hasAttempts }

  public init(
    id: Int, subjectID: Int64, assignmentID: Int64, srsStage: Int, availableAt: Int64 = 0,
    isLesson: Bool = false, isKanji: Bool = false, hasMeaning: Bool = true, hasReading: Bool = true
  ) {
    self.id = id
    self.subjectID = subjectID
    self.assignmentID = assignmentID
    self.srsStage = srsStage
    self.availableAt = availableAt
    self.isLesson = isLesson
    self.isKanji = isKanji
    self.hasMeaning = hasMeaning
    self.hasReading = hasReading
  }
}

public struct StudyQuestion: Codable, Equatable, Hashable, Sendable {
  public let itemID: Int
  public let kind: StudyQuestionKind
  public let revision: UInt64
}

public enum StudyAnswerDecision: String, Codable, Sendable {
  case correct, incorrect, overrideCorrect
}

/// A completed answer awaiting a durable outbox transaction. Practice sessions never produce one.
public struct StudyReviewSubmission: Codable, Equatable, Sendable {
  public let itemID: Int
  public let subjectID: Int64
  public let assignmentID: Int64
  public let isLesson: Bool
  public let meaningWrong: Bool
  public let readingWrong: Bool
  public let meaningWrongCount: Int
  public let readingWrongCount: Int
  public let createdAt: Int64?
  public init(
    itemID: Int, subjectID: Int64, assignmentID: Int64, isLesson: Bool,
    meaningWrong: Bool, readingWrong: Bool, meaningWrongCount: Int, readingWrongCount: Int,
    createdAt: Int64?
  ) {
    self.itemID = itemID
    self.subjectID = subjectID
    self.assignmentID = assignmentID
    self.isLesson = isLesson
    self.meaningWrong = meaningWrong
    self.readingWrong = readingWrong
    self.meaningWrongCount = meaningWrongCount
    self.readingWrongCount = readingWrongCount
    self.createdAt = createdAt
  }
}

public struct StudyMarkResult: Equatable, Sendable {
  public let subjectFinished: Bool
  public let didLevelUp: Bool
  /// Preserves the legacy local animation estimate; the server remains SRS authority.
  public let estimatedSRSStage: Int
  public let submission: StudyReviewSubmission?
}

public enum StudySessionError: Error, Equatable {
  case duplicateItemID
  case missingQuestionContent(Int)
  case staleQuestion, alreadyAnswered, invalidOverride
}

/// Deterministic, serializable study decisions, independent of UI, credentials and transport.
/// A host must durably enqueue each returned submission before presenting completion as saved.
public struct StudySession: Codable, Sendable {
  public var options: StudySessionOptions
  public let isPractice: Bool
  public let practiceScope: StudyPracticeScope?
  public private(set) var items: [Int: StudySessionItem]
  public private(set) var activeIDs: [Int] = []
  public private(set) var queuedIDs: [Int]
  public private(set) var completedIDs: [Int] = []
  public private(set) var question: StudyQuestion?
  public private(set) var tasksAnswered = 0
  public private(set) var tasksAnsweredCorrectly = 0
  public private(set) var wrappingUp = false
  private let batchSize: Int
  private var randomState: UInt64
  private var questionRevision: UInt64 = 0
  private var lastDecision: StudyAnswerDecision?
  private var lastMarkWasFirstAnswer = false

  public init(
    items: [StudySessionItem], options: StudySessionOptions = .init(), isPractice: Bool = false,
    practiceScope: StudyPracticeScope? = nil,
    seed: UInt64 = UInt64.random(in: .min ... .max)
  ) throws {
    guard Set(items.map(\.id)).count == items.count else { throw StudySessionError.duplicateItemID }
    if let empty = items.first(where: { !$0.hasMeaning && !$0.hasReading }) {
      throw StudySessionError.missingQuestionContent(empty.id)
    }
    self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    self.queuedIDs = items.map(\.id)
    self.options = options
    self.isPractice = isPractice
    self.practiceScope = practiceScope
    self.batchSize =
      options.groupMeaningReading || options.combinedAnki || isPractice
      ? 1 : max(1, options.batchSize)
    self.randomState = seed
    refill()
  }

  /// Durable stores derive newly completed answers from this state in the same transaction.
  public var completedSubmissions: [StudyReviewSubmission] {
    isPractice ? [] : completedIDs.compactMap { items[$0]?.submission }
  }

  public var currentDecision: StudyAnswerDecision? { lastDecision }

  public var canWrapUp: Bool { activeIDs.contains { items[$0]?.hasAttempts == true } }
  public var successRate: Int {
    tasksAnswered == 0 ? 100 : tasksAnsweredCorrectly * 100 / tasksAnswered
  }

  public mutating func setWrappingUp(_ value: Bool) {
    wrappingUp = value
    if value, let id = question?.itemID, items[id]?.hasAttempts == false,
      let index = activeIDs.firstIndex(of: id)
    {
      activeIDs.remove(at: index)
      queuedIDs.append(id)
    } else if !value {
      refill()
    }
  }

  @discardableResult public mutating func nextQuestion(continuingCurrentItem: Bool = false)
    -> StudyQuestion?
  {
    guard !activeIDs.isEmpty else { return nil }
    let id: Int
    if continuingCurrentItem || options.groupMeaningReading || isPractice,
      let current = question?.itemID,
      let item = items[current], !item.meaning.answered || !item.reading.answered,
      item.returnDelay == 0, activeIDs.contains(current)
    {
      id = current
    } else {
      var eligible = activeIDs.filter { items[$0]!.returnDelay == 0 }
      if eligible.isEmpty, !wrappingUp, !queuedIDs.isEmpty {
        let next = queuedIDs.removeFirst()
        activeIDs.append(next)
        eligible = [next]
      } else if eligible.isEmpty {
        eligible = activeIDs
      }
      for id in activeIDs where items[id]!.returnDelay > 0 { items[id]!.returnDelay -= 1 }
      id = eligible[randomIndex(count: eligible.count)]
    }
    let item = items[id]!
    let kind: StudyQuestionKind
    if item.meaning.answered || !item.hasMeaning {
      kind = .reading
    } else if item.reading.answered || !item.hasReading
      || (item.isKanji && options.skipKanjiReadings)
    {
      kind = .meaning
    } else if options.groupMeaningReading || options.combinedAnki || isPractice {
      kind = options.meaningFirst ? .meaning : .reading
    } else {
      kind = randomIndex(count: 2) == 0 ? .reading : .meaning
    }
    questionRevision &+= 1
    question = StudyQuestion(itemID: id, kind: kind, revision: questionRevision)
    lastDecision = nil
    lastMarkWasFirstAnswer = false
    return question
  }

  public mutating func deferQuestion(_ token: StudyQuestion) throws {
    try removeQuestion(token, requeue: true)
  }

  public mutating func excludeQuestion(_ token: StudyQuestion) throws {
    try removeQuestion(token, requeue: false)
  }

  /// Preserve the existing feedback behavior when a reading was entered for a meaning prompt.
  public mutating func creditReading(_ token: StudyQuestion) throws {
    try validate(token)
    guard token.kind == .meaning else { throw StudySessionError.staleQuestion }
    items[token.itemID]!.reading.answered = true
  }

  public mutating func mark(
    _ decision: StudyAnswerDecision, for token: StudyQuestion,
    now: Int64
  ) throws -> StudyMarkResult {
    try validate(token)
    guard lastDecision != .correct && lastDecision != .overrideCorrect else {
      throw StudySessionError.alreadyAnswered
    }
    if decision == .overrideCorrect, lastDecision != .incorrect {
      throw StudySessionError.invalidOverride
    }
    var item = items[token.itemID]!
    var attempt = token.kind == .meaning ? item.meaning : item.reading
    let first = attempt.firstAnswerWrong == nil
    let correct = decision != .incorrect
    if first || (lastMarkWasFirstAnswer && decision == .overrideCorrect) {
      attempt.firstAnswerWrong = !correct
      if decision == .overrideCorrect { attempt.wrongCount = max(0, attempt.wrongCount - 1) }
    }
    attempt.answered = correct
    if !correct { attempt.wrongCount += 1 }
    if token.kind == .meaning { item.meaning = attempt } else { item.reading = attempt }
    lastMarkWasFirstAnswer = first
    lastDecision = decision
    switch decision {
    case .correct:
      tasksAnswered += 1
      tasksAnsweredCorrectly += 1
      item.returnDelay = 0
    case .incorrect:
      tasksAnswered += 1
      item.returnDelay = max(0, options.incorrectAnswerDelay)
    case .overrideCorrect:
      tasksAnsweredCorrectly += 1
      item.returnDelay = 0
    }
    let finished =
      (item.meaning.answered || !item.hasMeaning)
      && (item.reading.answered || !item.hasReading || (item.isKanji && options.skipKanjiReadings))
    let levelUp =
      item.meaning.firstAnswerWrong != true && item.reading.firstAnswerWrong != true && !isPractice
    var submission: StudyReviewSubmission?
    if finished {
      if now > item.availableAt { item.createdAt = now }
      if options.minimizePenalty {
        if item.meaning.firstAnswerWrong == true { item.meaning.wrongCount = 1 }
        if item.reading.firstAnswerWrong == true { item.reading.wrongCount = 1 }
      }
      if !isPractice {
        submission = item.submission
      }
      completedIDs.append(item.id)
      activeIDs.removeAll { $0 == item.id }
      refill()
    }
    items[item.id] = item
    return StudyMarkResult(
      subjectFinished: finished, didLevelUp: levelUp,
      estimatedSRSStage: min(9, max(1, item.srsStage + (levelUp ? 1 : -1))), submission: submission)
  }

  private func validate(_ token: StudyQuestion) throws {
    guard question == token, activeIDs.contains(token.itemID) else {
      throw StudySessionError.staleQuestion
    }
  }

  private mutating func removeQuestion(_ token: StudyQuestion, requeue: Bool) throws {
    try validate(token)
    activeIDs.removeAll { $0 == token.itemID }
    items[token.itemID]!.meaning = .init()
    items[token.itemID]!.reading = .init()
    if requeue { queuedIDs.append(token.itemID) }
    question = nil
    lastDecision = nil
    refill()
  }

  private mutating func refill() {
    guard !wrappingUp else { return }
    while activeIDs.count < batchSize, !queuedIDs.isEmpty {
      activeIDs.append(queuedIDs.removeFirst())
    }
  }

  /// SplitMix64 with rejection sampling; the state survives a snapshot/restore unchanged.
  private mutating func randomIndex(count: Int) -> Int {
    let bound = UInt64(count)
    let threshold = (0 &- bound) % bound
    while true {
      randomState &+= 0x9E37_79B9_7F4A_7C15
      var value = randomState
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      value ^= value >> 31
      if value >= threshold { return Int(value % bound) }
    }
  }
}

extension StudySessionItem {
  fileprivate var submission: StudyReviewSubmission {
    StudyReviewSubmission(
      itemID: id, subjectID: subjectID, assignmentID: assignmentID,
      isLesson: isLesson, meaningWrong: meaning.firstAnswerWrong == true,
      readingWrong: reading.firstAnswerWrong == true,
      meaningWrongCount: meaning.wrongCount, readingWrongCount: reading.wrongCount,
      createdAt: createdAt)
  }
}
