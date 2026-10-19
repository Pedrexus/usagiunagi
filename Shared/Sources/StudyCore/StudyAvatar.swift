import CryptoKit
import Foundation

public enum StudyAvatar {
  public static let defaultURL = URL(
    string: "https://cdn.wanikani.com/default-avatar-300x300-20121121.png")!

  public static func email(custom: String, fallbacks: Data, accountID: String?) -> String {
    guard custom.isEmpty, let accountID,
      let values = try? PropertyListDecoder().decode([String: String].self, from: fallbacks)
    else { return custom }
    return values[accountID] ?? ""
  }

  /// Keep the original request URL so previously cached avatars remain usable.
  public static func url(email: String, pixelSize: Double) -> URL {
    let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !address.isEmpty else { return defaultURL }
    let hash = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
    var components = URLComponents(string: "https://www.gravatar.com/avatar/\(hash).jpg")!
    components.queryItems = [
      URLQueryItem(name: "s", value: String(pixelSize)),
      URLQueryItem(name: "d", value: defaultURL.absoluteString),
    ]
    return components.url!
  }
}
