// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore
import Testing

struct RecentMistakesTest {
  struct MergeCase: Sendable {
    let name: String
    let original: [Int64: Int]
    let other: [Int64: Int]
    let expected: [Int64: Int]
  }
  private let now = Date(timeIntervalSince1970: 1_792_195_200)
  private func dates(_ hours: [Int64: Int]) -> [Int64: Int64] {
    hours.mapValues { Int64(now.timeIntervalSince1970) + Int64($0) * 3600 }
  }
  @Test(arguments: [
    MergeCase(name: "empty", original: [:], other: [:], expected: [:]),
    MergeCase(
      name: "one array", original: [42: -10, 44: -4], other: [:], expected: [42: -10, 44: -4]),
    MergeCase(name: "old dates", original: [42: -42, 44: -88], other: [41: -33], expected: [:]),
    MergeCase(
      name: "different sets", original: [42: -10], other: [44: -4], expected: [42: -10, 44: -4]),
    MergeCase(name: "same data", original: [42: -10], other: [42: -10], expected: [42: -10]),
    MergeCase(
      name: "same subjects", original: [42: -10, 44: -4], other: [42: -10, 44: -4],
      expected: [42: -10, 44: -4]),
    MergeCase(name: "newest wins", original: [42: -10], other: [42: -4], expected: [42: -4]),
    MergeCase(
      name: "mixed conflicts", original: [42: -10, 44: -10, 46: -1], other: [42: -4, 46: -10],
      expected: [42: -4, 44: -10, 46: -1]),
    MergeCase(
      name: "same date", original: [42: -4], other: [44: -4, 46: -4],
      expected: [42: -4, 44: -4, 46: -4]),
  ])
  func originalMergeCorpusUsesNativeMaximumsAndWireAging(_ value: MergeCase) {
    for (lhs, rhs) in [(value.original, value.other), (value.other, value.original)] {
      let merged = StudyMistakeArchive.merge(dates(lhs), dates(rhs))
      #expect(
        StudyMistakeArchive.recentValues(merged, now: now) == dates(value.expected), "\(value.name)"
      )
    }
  }
}
