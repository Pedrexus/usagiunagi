import StudyCore
import SwiftUI

/// Subject identities from the original app; shared by study surfaces and charts.
public enum StudyPalette {
  public static let radical = Color(red: 0, green: 112.0 / 255, blue: 178.0 / 255)
  public static let kanji = Color(red: 206.0 / 255, green: 0, blue: 123.0 / 255)
  public static let vocabulary = Color(red: 145.0 / 255, green: 0, blue: 227.0 / 255)
  public static func color(for kind: SubjectKind) -> Color {
    switch kind {
    case .radical: radical
    case .kanji: kanji
    case .vocabulary: vocabulary
    }
  }
  public static func color(for category: StudySRSCategory) -> Color {
    switch category {
    case .apprentice: kanji
    case .guru: vocabulary
    case .master: Color(red: 47.0 / 255, green: 85.0 / 255, blue: 181.0 / 255)
    case .enlightened: Color(red: 47.0 / 255, green: 127.0 / 255, blue: 181.0 / 255)
    case .burned: .primary
    }
  }
}
