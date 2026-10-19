import Observation
import StudyCore

/// Per-window routes survive account bootstrap; no controller must be opened to queue a URL.
@Observable public final class StudyLinkInbox {
  public var pending: [StudyLink] = []
  public init() {}
  public func receive(_ link: StudyLink) {
    guard link != .activate, pending.last != link else { return }
    pending.append(link)
  }
}
