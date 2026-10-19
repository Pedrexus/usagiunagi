import SwiftUI

public enum StudyTab: Hashable, Sendable { case home, practice, statistics }

/// Both data backends use the same native adaptive navigation.
public struct StudyTabs<Home: View, Practice: View, Statistics: View>: View {
  @Binding private var selection: StudyTab
  private let home: Home
  private let practice: Practice
  private let statistics: Statistics
  private let showsPractice: Bool
  public init(
    selection: Binding<StudyTab>, showsPractice: Bool = true,
    @ViewBuilder home: () -> Home, @ViewBuilder practice: () -> Practice,
    @ViewBuilder statistics: () -> Statistics
  ) {
    _selection = selection
    self.showsPractice = showsPractice
    self.home = home()
    self.practice = practice()
    self.statistics = statistics()
  }
  public var body: some View {
    TabView(selection: $selection) {
      Tab(value: StudyTab.home) {
        home
      } label: {
        Label("Home", systemImage: "house").accessibilityIdentifier("navigation.Home")
      }
      if showsPractice {
        Tab(value: StudyTab.practice) {
          practice
        } label: {
          Label("Practice", systemImage: "square.and.pencil").accessibilityIdentifier(
            "navigation.Practice")
        }
      }
      Tab(value: StudyTab.statistics) {
        statistics
      } label: {
        Label("Stats", systemImage: "chart.bar.xaxis").accessibilityIdentifier(
          "navigation.Statistics")
      }
    }
    .tabViewStyle(.tabBarOnly)
  }
}
