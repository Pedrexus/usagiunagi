import Foundation

/// Offline cards from the original practice deck, including its repeated エ entry.
/// No account identifier, persistence writer or transport is part of a practice session.
public struct KatakanaPractice: Sendable {
  public static let characters = """
    ア イ ウ エ オ カ キ ク ケ コ キャ キュ キョ サ シ ス セ ソ シャ シュ ショ
    タ チ ツ テ ト チャ チュ チョ ナ ニ ヌ ネ ノ ニャ ニュ ニョ
    ハ ヒ フ ヘ ホ ヒャ ヒュ ヒョ マ ミ ム メ モ ミャ ミュ ミョ ヤ ユ エ ヨ
    ラ リ ル レ ロ リャ リュ リョ ワ ガ ギ グ ゲ ゴ ギャ ギュ ギョ
    ザ ジ ズ ゼ ゾ ジャ ジュ ジョ ダ ヂ ヅ デ ド ヂャ ヂュ ヂョ
    バ ビ ブ ベ ボ ビャ ビュ ビョ パ ピ プ ペ ポ ピャ ピュ ピョ ン
    """.split(whereSeparator: \.isWhitespace).map(String.init)
  public private(set) var session: StudySession
  public var question: StudyQuestion? {
    session.question.flatMap { session.activeIDs.contains($0.itemID) ? $0 : nil }
  }
  public var subject: GradingSubject? { question.map { Self.subject(at: $0.itemID) } }

  public static func subject(at index: Int) -> GradingSubject {
    let text = characters[index]
    return GradingSubject(
      japanese: text, kind: .vocabulary, meanings: [],
      primaryReadings: [text.applyingTransform(.hiraganaToKatakana, reverse: true)!])
  }

  public init(seed: UInt64 = .random(in: .min ... .max)) throws {
    session = try StudySession(
      items: Self.characters.indices.map {
        StudySessionItem(id: $0, subjectID: 0, assignmentID: 0, srsStage: 0, hasMeaning: false)
      }, isPractice: true, seed: seed)
    session.nextQuestion()
  }

  /// The question token rejects late callbacks after skipping or advancing.
  public mutating func answer(_ text: String, for token: StudyQuestion, convertRomaji: Bool = true)
    throws -> (grade: AnswerGrade, normalized: String, success: StudyMarkResult?)
  {
    guard question == token, let subject else { throw StudySessionError.staleQuestion }
    let input = convertRomaji ? KanaConverter.convert(text).text : text
    let normalized = AnswerGrader.normalizedString(input, taskType: .reading)
    let grade = AnswerGrader.checkNormalizedAnswer(
      normalized, subject: subject, synonyms: [], taskType: .reading, subjectLookup: { _ in nil })
    var success: StudyMarkResult?
    if grade == .precise || grade == .imprecise {
      success = try session.mark(.correct, for: token, now: 0)
      session.nextQuestion()
    } else if grade == .incorrect {
      _ = try session.mark(.incorrect, for: token, now: 0)
    }
    return (grade, normalized, success)
  }

  @discardableResult public mutating func correct(_ token: StudyQuestion) throws -> StudyMarkResult
  {
    let success = try session.mark(.overrideCorrect, for: token, now: 0)
    session.nextQuestion()
    return success
  }
  public mutating func advance(_ token: StudyQuestion) throws {
    guard question == token, session.currentDecision == .incorrect else {
      throw StudySessionError.staleQuestion
    }
    session.nextQuestion()
  }
  public mutating func deferQuestion(_ token: StudyQuestion) throws {
    try session.deferQuestion(token)
    session.nextQuestion()
  }
}
