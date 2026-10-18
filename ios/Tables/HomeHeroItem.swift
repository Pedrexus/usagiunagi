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

import SwiftUI

class HomeHeroItem: TableModelItem {
  let reviewCount: Int
  let lessonCount: Int
  // Shown instead of the lesson count's caption when lessons can't be started.
  let lessonsDisabledMessage: String?
  let leechCount: Int

  var startReviews: (() -> Void)?
  var startLessons: (() -> Void)?
  var showLessonPicker: (() -> Void)?
  var startLeechReviews: (() -> Void)?

  init(reviewCount: Int, lessonCount: Int, lessonsDisabledMessage: String?, leechCount: Int) {
    self.reviewCount = reviewCount
    self.lessonCount = lessonCount
    self.lessonsDisabledMessage = lessonsDisabledMessage
    self.leechCount = leechCount
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: HomeHeroCell.self)
  }
}

// The cell is a temporary table adapter; study actions use native SwiftUI controls.
class HomeHeroCell: TableModelCell {
  @TypedModelItem var item: HomeHeroItem
  override func update() {
    selectionStyle = .none
    backgroundConfiguration = .clear()
    contentConfiguration = UIHostingConfiguration { HomeStudyActions(item: item) }.margins(.all, 16)
  }
}

private struct HomeStudyActions: View {
  let item: HomeHeroItem
  private var lessonsEnabled: Bool { item.lessonCount > 0 && item.lessonsDisabledMessage == nil }
  var body: some View {
    VStack(spacing: 12) {
      action(
        "Start reviews", subtitle: "\(item.reviewCount) ready", symbol: "rectangle.stack",
        enabled: item.reviewCount > 0, prominent: true
      ) { item.startReviews?() }
      action(
        "Lessons", subtitle: item.lessonsDisabledMessage ?? "\(item.lessonCount) available",
        symbol: "book", enabled: lessonsEnabled
      ) { item.startLessons?() }
      action(
        "Extra practice", subtitle: "\(item.leechCount) items back in Apprentice",
        symbol: "arrow.trianglehead.2.clockwise.rotate.90", enabled: item.leechCount > 0
      ) { item.startLeechReviews?() }
      action("Choose lessons", symbol: "list.bullet", enabled: lessonsEnabled) {
        item.showLessonPicker?()
      }
    }
  }
  @ViewBuilder private func action(
    _ title: String, subtitle: String? = nil, symbol: String,
    enabled: Bool, prominent: Bool = false, perform: @escaping () -> Void
  ) -> some View {
    let button = Button(action: perform) {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.body.weight(.semibold))
          if let subtitle { Text(subtitle).font(.caption) }
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }.disabled(!enabled)
      .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
    if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
  }
}
