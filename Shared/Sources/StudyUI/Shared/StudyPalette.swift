import StudyCore
import SwiftUI

/// Subject identities from the original app; shared by study surfaces and charts.
public enum StudyPalette {
  public static let radical = Color(red: 43.0 / 255, green: 108.0 / 255, blue: 176.0 / 255)
  public static let kanji = Color(red: 184.0 / 255, green: 52.0 / 255, blue: 107.0 / 255)
  public static let vocabulary = Color(red: 116.0 / 255, green: 64.0 / 255, blue: 159.0 / 255)
  public static func color(for kind: SubjectKind) -> Color {
    switch kind {
    case .radical: radical
    case .kanji: kanji
    case .vocabulary: vocabulary
    }
  }
}
