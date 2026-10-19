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

class RecentMistakeHandler {
  var keyValueStore: NSUbiquitousKeyValueStore?
  var fileNamePrefix: String?
  private var dateFormatter: DateFormatter

  init() {
    dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
  }

  func setup(keyStore: NSUbiquitousKeyValueStore, storageFileNamePrefix: String?) {
    keyValueStore = keyStore
    fileNamePrefix = storageFileNamePrefix
    keyStore.synchronize()
  }

  func getCloudStorageKey() -> String {
    (fileNamePrefix ?? "") + "tsurukame-mistakes"
  }

  func getCloudMistakes() -> [Int32: Date] {
    guard let data = keyValueStore?.data(forKey: getCloudStorageKey()) else { return [:] }
    do {
      let mistakes = try JSONDecoder().decode([String: String].self, from: data)
      return mistakes.reduce(into: [:]) { result, item in
        if let id = Int32(item.key), let date = dateFormatter.date(from: item.value) {
          result[id] = date
        }
      }
    } catch {
      NSLog("Unable to deserialize mistakes from JSON: \(error)")
      return [:]
    }
  }

  func uploadMistakesToCloud(mistakes: [Int32: Date]) {
    do {
      // Preserve the original string keys and local date strings for existing iCloud clients.
      let archive = Dictionary(
        uniqueKeysWithValues: mistakes.map {
          (String($0.key), dateFormatter.string(from: $0.value))
        })
      keyValueStore?.set(try JSONEncoder().encode(archive), forKey: getCloudStorageKey())
      keyValueStore?.set(Date(), forKey: "lastSyncCall")
      keyValueStore?.synchronize()
    } catch {
      NSLog("Unable to serialize mistakes to JSON: \(error)")
    }
  }

  // Merge 2 dictionaries together and clean up any unnecessary data in the array along the way
  static func mergeMistakes(original: [Int32: Date], other: [Int32: Date]) -> [Int32: Date] {
    let dayAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
    return original.merging(other, uniquingKeysWith: max).filter { $0.value >= dayAgo }
  }
}
