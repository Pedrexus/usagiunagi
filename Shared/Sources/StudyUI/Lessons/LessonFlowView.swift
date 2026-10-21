import StudyCore
import SwiftUI

/// Direct subject/quiz navigation keeps the original study flow without a page-controller layout.
public struct LessonFlowView<Page: View>: View {
  private let subjects: [CatalogSubject]
  private let page: (Int) -> Page
  private let back: () -> Void
  private let backTitle: String
  private let playAudio: (Int) -> Void
  private let autoplay: ((Int) -> Void)?
  @State private var index = 0
  @FocusState private var keyboardFocus: Bool

  public init(
    subjects: [CatalogSubject], initialPage: Int = 0,
    backTitle: String = "Back",
    back: @escaping () -> Void,
    autoplay: ((Int) -> Void)? = nil,
    playAudio: @escaping (Int) -> Void, @ViewBuilder page: @escaping (Int) -> Page
  ) {
    self.subjects = subjects
    self._index = State(initialValue: min(subjects.count, max(0, initialPage)))
    self.back = back
    self.backTitle = backTitle
    self.playAudio = playAudio
    self.autoplay = autoplay
    self.page = page
  }
  public var body: some View {
    VStack(spacing: 0) {
      Group {
        if subjects.isEmpty {
          ContentUnavailableView(
            "No lessons available", systemImage: "books.vertical",
            description: Text("Return and refresh your account to check for new lessons."))
        } else {
          page(index).id(index).frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
              DragGesture(minimumDistance: 60).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 2 else {
                  return
                }
                index = min(subjects.count, max(0, index + (value.translation.width < 0 ? 1 : -1)))
              })
        }
      }
      if !subjects.isEmpty {
        HStack(spacing: 4) {
          Text(index == subjects.count ? "Quiz" : "\(index + 1)/\(subjects.count)")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            .accessibilityLabel(
              index == subjects.count ? "Quiz" : "Lesson \(index + 1) of \(subjects.count)"
            )
            .accessibilityIdentifier("lesson.position").padding(.leading, 12)
          ScrollViewReader { proxy in
            ScrollView(.horizontal) {
              HStack(spacing: 6) {
                ForEach(subjects.indices, id: \.self) { position in
                  Button {
                    index = position
                  } label: {
                    Group {
                      if subjects[position].japanese.isEmpty,
                        !subjects[position].characterImageURL.isEmpty,
                        let url = URL(string: subjects[position].characterImageURL)
                      {
                        RadicalImageView(url: url).environment(\.colorScheme, .dark)
                          .frame(width: 24, height: 24)
                      } else {
                        Text(
                          subjects[position].japanese.isEmpty
                            ? subjects[position].summary.meaning : subjects[position].japanese
                        )
                        .font(.title3)
                      }
                    }.padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44).foregroundStyle(
                      .white
                    )
                    .background(
                      StudyPalette.color(for: subjects[position].kind),
                      in: RoundedRectangle(cornerRadius: 10))
                  }.buttonStyle(.plain).id(position)
                    .accessibilityLabel(
                      [subjects[position].japanese, subjects[position].summary.meaning].filter {
                        !$0.isEmpty
                      }.joined(separator: ", ")
                    )
                    .accessibilityValue(index == position ? "Selected" : "Not selected")
                    .accessibilityAddTraits(index == position ? .isSelected : [])
                    .accessibilityIdentifier("lesson.page.\(position)")
                    .overlay {
                      if index == position {
                        RoundedRectangle(cornerRadius: 13).strokeBorder(.primary, lineWidth: 2)
                          .padding(-3).allowsHitTesting(false)
                      }
                    }
                }
                Button("Quiz") { index = subjects.count }.buttonStyle(.glass).tint(
                  .primary
                )
                .id(subjects.count).accessibilityValue(
                  index == subjects.count ? "Selected" : "Not selected"
                )
                .accessibilityIdentifier("lesson.quiz")
              }.padding(.horizontal, 6).padding(.vertical, 4)
            }.scrollIndicators(.hidden)
              .onChange(of: index) { _, value in proxy.scrollTo(value, anchor: .center) }
          }
        }.padding(.vertical, 4).background(.bar)
      }
    }.toolbar {
      ToolbarItem(placement: .navigation) {
        Button(backTitle, systemImage: "chevron.backward", action: back)
          .accessibilityIdentifier("lesson.back")
      }
      ToolbarItem(placement: .primaryAction) {
        if index < subjects.count {
          Button(index == subjects.count - 1 ? "Start quiz" : "Next") {
            index = min(subjects.count, index + 1)
          }
          .buttonStyle(.glassProminent).accessibilityIdentifier("lesson.next")
        }
      }.visibilityPriority(.high)
    }.toolbarTitleDisplayMode(.inline)
      .focusable(index < subjects.count).focused($keyboardFocus)
      .onAppear { keyboardFocus = index < subjects.count }
      .onChange(of: index, initial: true) { _, value in
        if subjects.indices.contains(value) { autoplay?(value) }
      }
      .onChange(of: index) { _, page in keyboardFocus = page < subjects.count }
      .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .space, "a", "d", "q", "j"]) { press in
        guard index < subjects.count, press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow, "a": index = max(0, index - 1)
        case .rightArrow, .return, "d": index += 1
        case "q": index = subjects.count
        case .space, "j":
          playAudio(index)
        default: return .ignored
        }
        return .handled
      }
  }
}
