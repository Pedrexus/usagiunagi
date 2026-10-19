import CryptoKit
import Foundation
import Security

/// Credentials stay outside the saved catalog and are owned by the app's account model.
@MainActor public protocol StudyCredentialStore {
  func load() throws -> String?
  func save(_ token: String) throws
  func remove() throws
}

public struct KeychainStudyCredentialStore: StudyCredentialStore {
  private let service: String
  private let account: String
  public init(service: String, account: String = "api-token") {
    self.service = service
    self.account = account
  }
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
  public func load() throws -> String? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return token
  }
  public func save(_ token: String) throws {
    let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var q = query
      q.merge(attributes) { _, new in new }
      try check(SecItemAdd(q as CFDictionary, nil))
    } else {
      try check(status)
    }
  }
  public func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }
}

public enum StudyCredentialID {
  public nonisolated static func forToken(_ token: String) -> String { forData(Data(token.utf8)) }
  nonisolated static func forData(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
