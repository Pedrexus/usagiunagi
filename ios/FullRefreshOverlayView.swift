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

struct FullRefreshOverlayView: View {
  let progress: Progress
  var body: some View {
    VStack(spacing: 16) {
      Text("Full refresh in progress…").font(.headline).accessibilityIdentifier("app.fullRefresh")
      ProgressView(progress).progressViewStyle(.linear).labelsHidden().frame(maxWidth: 280)
        .accessibilityLabel("WaniKani sync").accessibilityIdentifier("app.refreshProgress")
      Text("Updating your reviews and syncing your WaniKani account.")
        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial).contentShape(Rectangle())
  }
}
