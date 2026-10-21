import SwiftUI

public enum StudySettingsPage: String, Hashable, CaseIterable, Identifiable, Sendable {
  case appearance = "Appearance & Notifications"
  case lessons = "Lessons"
  case reviews = "Reviews"
  case subjects = "Radicals, Kanji & Vocabulary"
  public var id: Self { self }
  var symbol: String {
    switch self {
    case .appearance: "bell.badge"
    case .lessons: "book"
    case .reviews: "rectangle.and.pencil.and.ellipsis"
    case .subjects: "character.book.closed"
    }
  }
  var identifier: String {
    switch self {
    case .appearance: "appearance"
    case .lessons: "lessons"
    case .reviews: "reviews"
    case .subjects: "subjects"
    }
  }
}

/// Shared settings sections; each host supplies its current account and platform diagnostics.
public struct StudySettingsView<Destination: Hashable, Diagnostics: View, AccountActions: View>:
  View
{
  @Environment(\.studyCloudPreferences) private var cloudPreferences
  private let account: StudyShellState?
  private let model: StudyAppModel?
  private let destination: (StudySettingsPage) -> Destination
  private let diagnostics: Diagnostics
  private let accountActions: AccountActions
  public init(
    account: StudyShellState?, model: StudyAppModel? = nil,
    destination: @escaping (StudySettingsPage) -> Destination,
    @ViewBuilder diagnostics: () -> Diagnostics, @ViewBuilder accountActions: () -> AccountActions
  ) {
    self.account = account
    self.model = model
    self.destination = destination
    self.diagnostics = diagnostics()
    self.accountActions = accountActions()
  }
  public var body: some View {
    Form {
      if let account {
        Section {
          HStack(spacing: 14) {
            StudyAvatarView(url: account.avatar, revision: account.avatarRevision).frame(
              width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
              Text(account.username).font(.headline)
              Text("Level \(account.level) · WaniKani").font(.subheadline).foregroundStyle(
                .secondary)
            }
          }.padding(.vertical, 8)
        }
      }
      if let model { WaniKaniSettingsSection(model: model) }
      Section("App settings") {
        ForEach(StudySettingsPage.allCases) { page in
          NavigationLink(value: destination(page)) {
            Label(page.rawValue, systemImage: page.symbol)
          }
          .accessibilityIdentifier("settings.page.\(page.identifier)")
        }
      }
      if let cloudPreferences {
        Section("iCloud display settings") {
          Label(
            cloudPreferences.cloudEnabled ? "Private iCloud enabled" : "Saved on this device",
            systemImage: cloudPreferences.cloudEnabled ? "icloud" : "icloud.slash")
          Text(
            "Appearance, Japanese font size and SRS indicator. WaniKani remains the source of truth for study progress."
          )
          .font(.caption).foregroundStyle(.secondary)
          if let notice = cloudPreferences.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Section("Diagnostics") {
        let info = Bundle.main.infoDictionary ?? [:]
        LabeledContent("Version") {
          Text(
            "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
          )
          .textSelection(.enabled)
        }
        diagnostics
      }
      Section { accountActions }
      Section {
        Link(
          destination: URL(
            string:
              "https://github.com/Pedrexus/usagiunagi/issues/new?title=Visual%20redesign%20feedback"
          )!
        ) {
          Label("Give feedback on the new app look", systemImage: "bubble.left")
        }
      }
    }.formStyle(.grouped).navigationTitle("Settings").tint(StudyPalette.radical)
  }
}
