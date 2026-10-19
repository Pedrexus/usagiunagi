import Foundation

public enum StudyActivity: String, Sendable {
  case reviews = "com.tsurukame.reviews"
  case lessons = "com.tsurukame.lessons"
}

/// Navigation only. URLs never supply credentials, answers or upload instructions.
public enum StudyLink: Equatable, Hashable, Sendable {
  public enum Subject: Equatable, Hashable, Sendable {
    case id(Int64)
    case japanese(SubjectKind, String)
  }
  case activate, reviews, lessons, wrapUp
  case subject(Subject)

  public init(activity: StudyActivity) {
    self = activity == .reviews ? .reviews : .lessons
  }
  public init?(url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = parts.scheme?.lowercased(), parts.user == nil, parts.password == nil,
      parts.port == nil || (scheme == "https" && parts.port == 443)
    else { return nil }
    let custom = scheme == "usagiunagi" || scheme == "tsurukame"
    guard custom || (scheme == "https" && parts.host?.lowercased() == "tsurukame.app") else {
      return nil
    }
    var segments: [String] = []
    if custom, let host = parts.host, !host.isEmpty { segments.append(host) }
    for segment in parts.percentEncodedPath.split(separator: "/") {
      guard let decoded = String(segment).removingPercentEncoding else { return nil }
      segments.append(decoded)
    }
    guard let head = segments.first?.lowercased() else {
      self = .activate
      return
    }
    switch (head, segments.count) {
    case ("reviews", 1): self = .reviews
    case ("lessons", 1): self = .lessons
    case ("wrap-up", 1): self = .wrapUp
    case ("subject", 2):
      guard let id = Int64(segments[1]), id > 0 else { return nil }
      self = .subject(.id(id))
    case ("radical", 2), ("kanji", 2), ("vocabulary", 2):
      guard let kind = SubjectKind(rawValue: head),
        !segments[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      self = .subject(.japanese(kind, segments[1]))
    default: return nil
    }
  }
  public var title: String {
    switch self {
    case .activate: "Open app"
    case .reviews: "Open reviews"
    case .lessons: "Open lessons"
    case .wrapUp: "Wrap up reviews"
    case .subject: "Open subject"
    }
  }
}
