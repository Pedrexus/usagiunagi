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

/// Existing answer-typo distance, preserved over UTF-16 code units.
/// Uses adjacent transpositions (optimal string alignment), not unrestricted Damerau distance.
public enum AnswerDistance {
  public static func between(_ first: String, _ second: String) -> Int {
    var a = Array(first.utf16)
    var b = Array(second.utf16)
    if a.count < b.count { swap(&a, &b) }
    guard !b.isEmpty else { return a.count }
    var older = Array(repeating: 0, count: b.count + 1)
    var previous = Array(0...b.count)
    var current = older
    for i in 1...a.count {
      current[0] = i
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
          current[j] = min(current[j], older[j - 2] + cost)
        }
      }
      swap(&older, &previous)
      swap(&previous, &current)
    }
    return previous[b.count]
  }
}
