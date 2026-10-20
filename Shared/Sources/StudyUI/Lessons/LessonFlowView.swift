import StudyCore
import SwiftUI

/// Direct subject/quiz navigation keeps the original study flow without a page-controller layout.
public struct LessonFlowView<Page: View>: View {
  private let subjects: [StudySubject]
  private let japaneseFont: String?
  private let image: (Int64) -> Image?
  private let page: (Int) -> Page
  private let back: () -> Void
  private let backTitle: String
  private let playAudio: (Int) -> Void
  @State private var index = 0
  @FocusState private var keyboardFocus: Bool

  public init(
    subjects: [StudySubject], initialPage: Int = 0, japaneseFont: String? = nil,
    image: @escaping (Int64) -> Image? = { _ in nil }, backTitle: String = "Back",
    back: @escaping () -> Void,
    playAudio: @escaping (Int) -> Void, @ViewBuilder page: @escaping (Int) -> Page
  ) {
    self.subjects = subjects
    self._index = State(initialValue: min(subjects.count, max(0, initialPage)))
    self.japaneseFont = japaneseFont
    self.image = image
    self.back = back
    self.backTitle = backTitle
    self.playAudio = playAudio
    self.page = page
  }
  public var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
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
        Button(backTitle, systemImage: "chevron.backward", action: back).buttonStyle(.glass)
          .padding(8).accessibilityIdentifier(
            "lesson.back")
      }
      if !subjects.isEmpty {
        VStack(spacing: 4) {
          Text(index == subjects.count ? "Quiz" : "Lesson \(index + 1) of \(subjects.count)")
            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("lesson.position")
          ScrollViewReader { proxy in
            ScrollView(.horizontal) {
              HStack(spacing: 10) {
                ForEach(subjects.indices, id: \.self) { position in
                  Button {
                    index = position
                  } label: {
                    Group {
                      if let image = image(subjects[position].id) {
                        image.resizable().scaledToFit().frame(width: 24, height: 24)
                      } else {
                        Text(
                          subjects[position].characters.isEmpty
                            ? subjects[position].meaning : subjects[position].characters
                        )
                        .font(japaneseFont.map { .custom($0, size: 20) } ?? .title3)
                      }
                    }.padding(.horizontal, 12).frame(minWidth: 44, minHeight: 36).foregroundStyle(
                      .white
                    )
                    .background(
                      StudyPalette.color(for: subjects[position].kind),
                      in: RoundedRectangle(cornerRadius: 10))
                  }.buttonStyle(.plain).id(position)
                    .accessibilityLabel(
                      [subjects[position].characters, subjects[position].meaning].filter {
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
                Button("Quiz") { index = subjects.count }.buttonStyle(.borderedProminent).tint(
                  .primary
                )
                .id(subjects.count).accessibilityValue(
                  index == subjects.count ? "Selected" : "Not selected"
                )
                .accessibilityIdentifier("lesson.quiz")
              }.padding(.horizontal, 16).padding(.vertical, 4)
            }.scrollIndicators(.hidden)
              .onChange(of: index) { _, value in proxy.scrollTo(value, anchor: .center) }
          }
        }.padding(.vertical, 8).background(.bar)
      }
    }.focusable(index < subjects.count).focused($keyboardFocus)
      .onAppear { keyboardFocus = index < subjects.count }
      .onChange(of: index) { _, page in keyboardFocus = page < subjects.count }
      .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .space, "a", "d", "q", "j"]) { press in
        guard index < subjects.count else { return .ignored }
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
