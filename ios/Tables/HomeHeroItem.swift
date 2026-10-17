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

import UIKit

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

// Keep review and lesson behavior in the existing controller, using native controls here.
class HomeHeroCell: TableModelCell {
  @TypedModelItem var item: HomeHeroItem

  private let reviews = UIButton(type: .system)
  private let lessons = UIButton(type: .system)
  private let leeches = UIButton(type: .system)
  private let picker = UIButton(type: .system)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    let stack = UIStackView(arrangedSubviews: [reviews, lessons, leeches, picker])
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
      stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
    ])
    for button in [reviews, lessons, leeches, picker] {
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.titleLabel?.numberOfLines = 0
    }
    reviews.addAction(UIAction { [weak self] _ in self?.item.startReviews?() }, for: .touchUpInside)
    lessons.addAction(UIAction { [weak self] _ in self?.item.startLessons?() }, for: .touchUpInside)
    leeches.addAction(UIAction { [weak self] _ in self?.item.startLeechReviews?() },
                      for: .touchUpInside)
    picker.addAction(UIAction { [weak self] _ in self?.item.showLessonPicker?() },
                     for: .touchUpInside)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func update() {
    backgroundConfiguration = .clear()
    configure(reviews, title: "Start reviews", subtitle: "\(item.reviewCount) ready",
              symbol: "rectangle.stack",
              enabled: item.reviewCount > 0, prominent: true)
    configure(lessons, title: "Lessons",
              subtitle: item.lessonsDisabledMessage ?? "\(item.lessonCount) available",
              symbol: "book", enabled: item.lessonCount > 0 && item.lessonsDisabledMessage == nil)
    configure(leeches, title: "Extra practice",
              subtitle: "\(item.leechCount) items back in Apprentice",
              symbol: "arrow.trianglehead.2.clockwise.rotate.90", enabled: item.leechCount > 0)
    configure(picker, title: "Choose lessons", subtitle: nil, symbol: "list.bullet",
              enabled: lessons.isEnabled)
  }

  private func configure(_ button: UIButton, title: String, subtitle: String?, symbol: String,
                         enabled: Bool, prominent: Bool = false) {
    var config: UIButton.Configuration
    if #available(iOS 26.0, *) {
      config = prominent ? .prominentGlass() : .glass()
    } else {
      config = prominent ? .filled() : .tinted()
    }
    config.title = title
    config.subtitle = subtitle
    config.image = UIImage(systemName: symbol) ?? UIImage(systemName: "arrow.clockwise")
    config.imagePadding = 12
    config.titleAlignment = .leading
    config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    button.configuration = config
    button.contentHorizontalAlignment = .leading
    button.isEnabled = enabled
    button.accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
  }
}
