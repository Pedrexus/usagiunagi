import SwiftUI

public enum StudyTab: Hashable, Sendable { case home, practice, statistics }

/// iPhone tabs adapt through the system's larger-window navigation.
struct StudyTabs<Home: View, Practice: View, Statistics: View>: View {
  @Binding var selection: StudyTab
  @ViewBuilder let home: Home
  @ViewBuilder let practice: Practice
  @ViewBuilder let statistics: Statistics
  var body: some View {
    TabView(selection: $selection) {
      Tab(value: StudyTab.home) {
        home
      } label: {
        Label("Home", systemImage: "house").accessibilityIdentifier("navigation.Home")
      }
      Tab(value: StudyTab.practice) {
        practice
      } label: {
        Label("Practice", systemImage: "square.and.pencil").accessibilityIdentifier(
          "navigation.Practice")
      }
      Tab(value: StudyTab.statistics) {
        statistics
      } label: {
        Label("Stats", systemImage: "chart.bar.xaxis").accessibilityIdentifier(
          "navigation.Statistics")
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}
