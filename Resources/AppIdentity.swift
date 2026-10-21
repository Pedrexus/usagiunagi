import Foundation

/// The localized display name is shared by the app bundle and visible UI.
enum AppIdentity {
  static var name: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "usagiunagi"
  }
}
