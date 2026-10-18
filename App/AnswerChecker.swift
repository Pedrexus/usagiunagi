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
import StudyCore
import WaniKaniAPI

/// Compatibility boundary for the existing protobuf-backed app and review controller.
/// Grading and normalization are implemented once in StudyCore.
enum AnswerChecker {
  typealias AnswerCheckerResult = AnswerGrade

  static func convertKatakanaToHiragana(_ text: String) -> String {
    AnswerGrader.convertKatakanaToHiragana(text)
  }

  static func normalizedString(_ text: String, taskType: TaskType,
                               alphabet: KanaAlphabet = .hiragana) -> String {
    AnswerGrader.normalizedString(text, taskType: taskType, alphabet: alphabet)
  }

  static func checkAnswer(_ answer: String, subject: TKMSubject, studyMaterials: TKMStudyMaterials?,
                          taskType: TaskType,
                          localCachingClient: LocalCachingClient) -> AnswerGrade {
    checkAnswer(answer, subject: subject, studyMaterials: studyMaterials, taskType: taskType,
                subjectLookup: { localCachingClient.getSubject(id: $0) })
  }

  static func checkAnswer(_ answer: String, subject: TKMSubject, studyMaterials: TKMStudyMaterials?,
                          taskType: TaskType,
                          subjectLookup: (Int64) -> TKMSubject?) -> AnswerGrade {
    AnswerGrader.checkNormalizedAnswer(answer, subject: subject.gradingSubject,
                                       synonyms: studyMaterials?.meaningSynonyms ?? [],
                                       taskType: taskType,
                                       subjectLookup: { subjectLookup($0)?.gradingSubject })
  }
}

extension TKMSubject {
  var gradingSubject: GradingSubject {
    GradingSubject(japanese: japanese,
                   kind: hasKanji ? .kanji : hasVocabulary ? .vocabulary : .radical,
                   meanings: meanings.filter { $0.type != .blacklist }.map(\.meaning),
                   blacklistedMeanings: meanings.filter { $0.type == .blacklist }.map(\.meaning),
                   primaryReadings: primaryReadings.map(\.reading),
                   alternateReadings: alternateReadings.map(\.reading),
                   componentSubjectIds: componentSubjectIds)
  }
}
