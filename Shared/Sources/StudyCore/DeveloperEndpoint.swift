import Foundation

public enum DeveloperEndpoint {
  /// Preserve custom HTTP(S) test servers and the existing empty-to-default behavior.
  public static func normalized(_ text: String, defaultURL: String) -> String? {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if value.isEmpty { return defaultURL }
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty
    else { return nil }
    return value
  }
}
