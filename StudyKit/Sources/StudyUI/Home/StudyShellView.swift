import Foundation
import SwiftUI

@Observable public final class StudyShellState {
  public var username = ""
  public var level = 0
  public var learnedKanji = 0
  public var avatar: URL?
  public var avatarRevision = 0
  public var onVacation = false
  public var progress: Progress?
  public var blockingProgress: Progress?
  public init() {}
}

public struct StudyShellView<Content: View>: View {
  let state: StudyShellState
  let search: () -> Void
  let settings: () -> Void
  let content: Content

  public init(
    state: StudyShellState, search: @escaping () -> Void, settings: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.state = state
    self.search = search
    self.settings = settings
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Group {
          if let url = state.avatar {
            AsyncImage(request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)) {
              image in
              image.resizable().scaledToFill()
            } placeholder: {
              Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
          } else {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
          }
        }.frame(width: 42, height: 42).clipShape(Circle()).accessibilityHidden(true)
          .id(state.avatarRevision)
        VStack(alignment: .leading, spacing: 3) {
          Text(state.username).font(.headline).accessibilityIdentifier("app.username")
          Text("Level \(state.level) · \(state.learnedKanji.formatted()) kanji learned")
            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("app.level")
        }.frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
          Button("Search", systemImage: "magnifyingglass", action: search).accessibilityIdentifier(
            "app.search")
          Button("Settings", systemImage: "gearshape", action: settings).accessibilityIdentifier(
            "app.settings")
        }.labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
      }.padding(.horizontal, 16).padding(.vertical, 8)
      if state.onVacation {
        VStack(alignment: .leading, spacing: 6) {
          Label("Vacation mode", systemImage: "pause.circle").font(.headline)
            .accessibilityIdentifier("app.vacation")
          Text(
            "Your account is on vacation, so lessons and reviews are paused. Turn off vacation mode on the WaniKani website."
          )
          .font(.callout).foregroundStyle(.secondary)
          Link("Open WaniKani", destination: URL(string: "https://www.wanikani.com")!)
            .font(.callout).accessibilityIdentifier("app.vacation.website")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
          .background(StudyPalette.kanji.opacity(0.1))
      }
      if let progress = state.progress {
        ProgressView(progress).progressViewStyle(.linear).labelsHidden()
          .accessibilityLabel("WaniKani sync").accessibilityIdentifier("app.syncProgress")
      }
      content.ignoresSafeArea(.container, edges: .bottom)
    }.background(.background).tint(StudyPalette.radical)
      .disabled(state.blockingProgress != nil)
  }
}
