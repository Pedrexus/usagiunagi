import Foundation

/// Immutable study references ship locally; account data belongs in the store.
enum StudyResources {
  static func decode<Value: Decodable>(_ name: String) throws -> Value {
    guard let url = Bundle.module.url(forResource: name, withExtension: "plist") else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return try PropertyListDecoder().decode(Value.self, from: Data(contentsOf: url))
  }
}
