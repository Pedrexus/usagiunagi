import SwiftUI

public struct StudyAvatarView: View {
  let url: URL?
  let revision: Int
  public init(url: URL?, revision: Int = 0) {
    self.url = url
    self.revision = revision
  }
  public var body: some View {
    Group {
      if let url {
        AsyncImage(request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          placeholder
        }
      } else {
        placeholder
      }
    }.clipShape(Circle()).accessibilityHidden(true).id(url).id(revision)
  }
  private var placeholder: some View {
    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
  }
}
