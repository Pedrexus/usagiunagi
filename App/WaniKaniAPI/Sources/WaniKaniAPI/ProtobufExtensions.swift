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

extension TKMVocabulary.PartOfSpeech: CustomStringConvertible {
  public var description: String {
    switch self {
    case .noun:
      return "Noun"
    case .numeral:
      return "Numeral"
    case .intransitiveVerb:
      return "Intransitive Verb"
    case .ichidanVerb:
      return "Ichidan Verb"
    case .transitiveVerb:
      return "Transitive Verb"
    case .noAdjective:
      return "No Adjective"
    case .godanVerb:
      return "Godan Verb"
    case .naAdjective:
      return "Na Adjective"
    case .iAdjective:
      return "I Adjective"
    case .suffix:
      return "Suffix"
    case .adverb:
      return "Adverb"
    case .suruVerb:
      return "Suru Verb"
    case .prefix:
      return "Prefix"
    case .properNoun:
      return "Proper Noun"
    case .expression:
      return "Expression"
    case .adjective:
      return "Adjective"
    case .interjection:
      return "Interjection"
    case .counter:
      return "Counter"
    case .pronoun:
      return "Pronoun"
    case .conjunction:
      return "Conjunction"
    default:
      return ""
    }
  }
}
