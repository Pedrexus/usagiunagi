import StudyCore
import SwiftUI

extension EnvironmentValues {
  @Entry public var studyAvatars: LegacyAvatarCache? = nil
}

struct StudyAvatarView: View {
  let url: URL?
  let revision: Int
  @Environment(\.studyAvatars) private var cache
  @State private var loaded: (request: Request, image: CGImage)?
  private struct Request: Equatable {
    let url: URL?
    let revision: Int
    let cacheID: ObjectIdentifier?
  }
  var body: some View {
    let request = Request(url: url, revision: revision, cacheID: cache.map(ObjectIdentifier.init))
    Group {
      if let loaded, loaded.request == request {
        Image(decorative: loaded.image, scale: 1).resizable().scaledToFill()
      } else {
        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
      }
    }.clipShape(Circle()).accessibilityHidden(true)
      .task(id: request) {
        loaded = nil
        guard let url, let cache else { return }
        if let image = try? await cache.image(at: url), !Task.isCancelled {
          loaded = (request, image)
        }
      }
  }
}
