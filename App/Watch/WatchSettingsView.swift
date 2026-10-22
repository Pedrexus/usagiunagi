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
import SwiftUI

struct WatchSettingsView: View {
  @AppStorage(WatchCompanionCache.sourceKey) private var source = ComplicationDataSource.reviews
    .rawValue
  @State private var snapshot = WatchCompanionCache.sharedInstance.state.snapshot
  @State private var clockStart = Date.now

  var body: some View {
    TimelineView(.periodic(from: clockStart, by: 60)) { context in
      Form {
        Section("Data Source") {
          Picker("Show", selection: selection) {
            Text("Review Counts").tag(ComplicationDataSource.reviews.rawValue)
            Text("Level").tag(ComplicationDataSource.level.rawValue)
          }
        }
        Section("Last Updated") {
          if let snapshot {
            Text(snapshot.sentAt, style: .relative)
            if context.date >= snapshot.expiresAt {
              Label(
                "The data on this watch is stale. Open the app on your phone to update.",
                systemImage: "exclamationmark.triangle")
            }
          } else {
            Text("No data. Open the app on your phone to update.")
          }
        }
      }
    }
    .navigationTitle("Settings")
    .task {
      snapshot = WatchCompanionCache.sharedInstance.state.snapshot
      for await _ in NotificationCenter.default.notifications(
        named: UserDefaults.didChangeNotification)
      {
        guard !Task.isCancelled else { return }
        snapshot = WatchCompanionCache.sharedInstance.state.snapshot
      }
    }
  }

  private var selection: Binding<Int> {
    Binding(
      get: {
        ComplicationDataSource(rawValue: source)?.rawValue
          ?? ComplicationDataSource.reviews.rawValue
      },
      set: { value in
        guard value != source else { return }
        source = value
        WatchHelper.reloadComplications()
      })
  }
}
