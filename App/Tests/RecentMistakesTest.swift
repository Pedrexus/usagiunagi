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
import Testing

struct RecentMistakesTest {
  @Test func testEmptyMergeGivesNothing() {
    let output = RecentMistakeHandler.mergeMistakes(
      original: [Int32: Date](),
      other: [Int32: Date]())
    #expect(0 == output.count)
  }

  @Test func testMergeMistakesOneArrayOnly() {
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let mistakes = [Int32(42): firstDate, Int32(44): secondDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: [Int32: Date]())
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: [Int32: Date](), other: mistakes)
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
  }

  @Test func testOldDatesRemoved() {
    // dates older than 24 hrs should be removed
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -42, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -88, to: now)!
    let thirdDate = Calendar.current.date(byAdding: .hour, value: -33, to: now)!
    let mistakes = [Int32(42): firstDate, Int32(44): secondDate]
    let otherMistakes = [Int32(41): thirdDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(0 == output.count)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(0 == output.count)
  }

  @Test func testSimpleMergeTwoDiffDatasets() {
    // simple merge of two sets with two different pieces of data
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let mistakes = [Int32(42): firstDate]
    let otherMistakes = [Int32(44): secondDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
  }

  @Test func testSimpleMergeSameDataDatasets() {
    // simple merge of two sets with same pieces of data
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let mistakes = [Int32(42): firstDate]
    let otherMistakes = [Int32(42): firstDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(1 == output.count)
    #expect(output[42] == firstDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(1 == output.count)
    #expect(output[42] == firstDate)
  }

  @Test func testSimpleMergeSameDatasetsMultipleSubjects() {
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let mistakes = [Int32(42): firstDate, Int32(44): secondDate]
    let otherMistakes = [Int32(42): firstDate, Int32(44): secondDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(2 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
  }

  @Test func testSubjectIdConflictMerge() {
    // we expect to get the newer date when there is a date conflict
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let mistakes = [Int32(42): firstDate]
    let otherMistakes = [Int32(42): secondDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(1 == output.count)
    #expect(output[42] == secondDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(1 == output.count)
    #expect(output[42] == secondDate)
  }

  @Test func testSubjectIdConflictMergeMultipleSubjects() {
    // we expect to get the newer date when there is a date conflict
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -10, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let thirdDate = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
    let mistakes = [Int32(42): firstDate, Int32(44): firstDate, Int32(46): thirdDate]
    let otherMistakes = [Int32(42): secondDate, Int32(46): firstDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(3 == output.count)
    #expect(output[42] == secondDate)
    #expect(output[44] == firstDate)
    #expect(output[46] == thirdDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(3 == output.count)
    #expect(output[42] == secondDate)
    #expect(output[44] == firstDate)
    #expect(output[46] == thirdDate)
  }

  @Test func testSameDateDifferentSubjectsMerge() {
    // we expect to get the newer date when there is a date conflict
    let now = Date()
    let firstDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let secondDate = Calendar.current.date(byAdding: .hour, value: -4, to: now)!
    let mistakes = [Int32(42): firstDate]
    let otherMistakes = [Int32(44): secondDate, Int32(46): secondDate]
    var output = RecentMistakeHandler.mergeMistakes(original: mistakes, other: otherMistakes)
    #expect(3 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
    #expect(output[46] == secondDate)
    // ensure that flopping the dictionaries gets same output
    output = RecentMistakeHandler.mergeMistakes(original: otherMistakes, other: mistakes)
    #expect(3 == output.count)
    #expect(output[42] == firstDate)
    #expect(output[44] == secondDate)
    #expect(output[46] == secondDate)
  }
  @Test func oldCloudArchiveSkipsOnlyInvalidEntries() throws {
    let store = MemoryMistakeStore()
    let handler = RecentMistakeHandler()
    handler.setup(keyStore: store, storageFileNamePrefix: "fixture-")
    let date = "2026-10-17 12:34:56"
    store.values[handler.getCloudStorageKey()] = try JSONSerialization.data(withJSONObject: [
      "42": date, "bad-id": date, "2147483648": date, "43": "invalid date",
    ])
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    #expect(handler.getCloudMistakes() == [42: try #require(formatter.date(from: date))])
    #expect(store.values.keys.sorted() == ["fixture-tsurukame-mistakes"])
  }
  @Test func newCloudArchiveRemainsReadableByTheOriginalJSONFormat() throws {
    let store = MemoryMistakeStore()
    let handler = RecentMistakeHandler()
    handler.setup(keyStore: store, storageFileNamePrefix: "fixture-")
    let date = Date(timeIntervalSince1970: 1_792_195_200)
    handler.uploadMistakesToCloud(mistakes: [42: date])
    let data = try #require(store.values[handler.getCloudStorageKey()])
    let oldReader = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    #expect(oldReader == ["42": formatter.string(from: date)])
    #expect(handler.getCloudMistakes() == [42: date])
    #expect(store.lastSyncCall != nil)
    handler.uploadMistakesToCloud(mistakes: [:])
    #expect(handler.getCloudMistakes().isEmpty)
  }
  @Test(arguments: ["not JSON", "[]", "{\"42\":123}"])
  func unreadableCloudArchiveDoesNotInventOrRewriteMistakes(json: String) {
    let store = MemoryMistakeStore()
    let handler = RecentMistakeHandler()
    handler.setup(keyStore: store, storageFileNamePrefix: "fixture-")
    let data = Data(json.utf8)
    store.values[handler.getCloudStorageKey()] = data
    #expect(handler.getCloudMistakes().isEmpty)
    #expect(store.values[handler.getCloudStorageKey()] == data && store.lastSyncCall == nil)
  }

}

/// No reads, writes or synchronization reach the system iCloud store.
private final class MemoryMistakeStore: NSUbiquitousKeyValueStore {
  var values: [String: Data] = [:]
  var lastSyncCall: Date?
  override func data(forKey key: String) -> Data? { values[key] }
  override func set(_ data: Data?, forKey key: String) { values[key] = data }
  override func set(_ value: Any?, forKey key: String) {
    #expect(key == "lastSyncCall")
    lastSyncCall = value as? Date
  }
  override func synchronize() -> Bool { true }
}
