import Foundation

public enum StudyMistakeError: Error, LocalizedError {
  case invalidArchive, unsupportedVersion, accountMismatch, invalidKey, quotaExceeded, unavailable
  public var errorDescription: String? {
    switch self {
    case .invalidArchive:
      "Saved iCloud mistake history could not be read. It has been kept unchanged."
    case .unsupportedVersion:
      "This iCloud mistake history needs a newer app. It has been kept unchanged."
    case .accountMismatch: "The iCloud mistake history belongs to another WaniKani account."
    case .invalidKey: "This account cannot use the iCloud mistake-history key."
    case .quotaExceeded:
      "iCloud mistake history is full. Recent mistakes are still saved on this device."
    case .unavailable:
      "iCloud mistake sync is unavailable. Recent mistakes are still saved on this device."
    }
  }
}

/// Absolute practice hints only. This document never authorizes a review or assignment change.
public struct StudyMistakeArchive: Codable, Equatable, Sendable {
  private struct Entry: Codable, Equatable, Sendable {
    let subjectID: Int64
    let timestamp: Int64
    private enum CodingKeys: String, CodingKey { case subjectID, timestamp }
    init(subjectID: Int64, timestamp: Int64) {
      self.subjectID = subjectID
      self.timestamp = timestamp
    }
    init(from decoder: any Decoder) throws {
      try StudyMistakeArchive.rejectUnknownFields(decoder, keys: CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      subjectID = try container.decode(Int64.self, forKey: .subjectID)
      timestamp = try container.decode(Int64.self, forKey: .timestamp)
    }
  }
  private struct Field: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  private static func rejectUnknownFields<Key: CodingKey>(_ decoder: any Decoder, keys: Key.Type)
    throws
  {
    let fields = try decoder.container(keyedBy: Field.self).allKeys
    guard fields.allSatisfy({ Key(stringValue: $0.stringValue) != nil }) else {
      throw StudyMistakeError.invalidArchive
    }
  }
  public static let maximumBytes = 1_048_576
  public let formatVersion: Int
  public let accountID: String
  private let entries: [Entry]
  public var values: [Int64: Int64] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.subjectID, $0.timestamp) })
  }
  public init(accountID: String, values: [Int64: Int64]) throws {
    guard !accountID.isEmpty else { throw StudyMistakeError.accountMismatch }
    guard values.allSatisfy({ $0.key > 0 && $0.value >= 0 }) else {
      throw StudyMistakeError.invalidArchive
    }
    formatVersion = 1
    self.accountID = accountID
    entries = values.map { Entry(subjectID: $0.key, timestamp: $0.value) }
      .sorted { $0.subjectID < $1.subjectID }
  }
  private enum CodingKeys: String, CodingKey { case formatVersion, accountID, entries }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .formatVersion)
    guard version == 1 else { throw StudyMistakeError.unsupportedVersion }
    try Self.rejectUnknownFields(decoder, keys: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .accountID)
    let entries = try container.decode([Entry].self, forKey: .entries)
    guard Set(entries.map(\.subjectID)).count == entries.count else {
      throw StudyMistakeError.invalidArchive
    }
    try self.init(
      accountID: id,
      values: Dictionary(
        uniqueKeysWithValues: entries.map { ($0.subjectID, $0.timestamp) }))
  }
  public init(data: Data, accountID: String) throws {
    guard data.count <= Self.maximumBytes else { throw StudyMistakeError.quotaExceeded }
    self = try PropertyListDecoder().decode(Self.self, from: data)
    guard self.accountID == accountID else { throw StudyMistakeError.accountMismatch }
  }
  public func encoded() throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw StudyMistakeError.quotaExceeded }
    return data
  }
  public static func key(accountID: String) throws -> String {
    let key = "usagiunagi.mistakes.v1." + accountID
    guard !accountID.isEmpty, key.utf16.count <= 128 else { throw StudyMistakeError.invalidKey }
    return key
  }
  public static func merge(_ lhs: [Int64: Int64], _ rhs: [Int64: Int64]) -> [Int64: Int64] {
    lhs.merging(rhs, uniquingKeysWith: max)
  }
  /// Only the wire ages out. Future instants remain unchanged; practice eligibility is separate.
  public static func recentValues(_ values: [Int64: Int64], now: Date) -> [Int64: Int64] {
    let cutoff = now.addingTimeInterval(-86_400).timeIntervalSince1970
    return values.filter { Double($0.value) >= cutoff }
  }
}
