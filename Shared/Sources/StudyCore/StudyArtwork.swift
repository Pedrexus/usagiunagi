// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation

/// Original @AmandaBear artwork lookup, stored as data rather than Swift source.
public struct StudyArtwork: Sendable {
  let paths: [Int64: String]
  public init(data: Data) throws {
    paths = try PropertyListDecoder().decode([Int64: String].self, from: data)
  }
  public static func bundled() throws -> Self {
    guard let url = Bundle.module.url(forResource: "artwork", withExtension: "plist") else {
      throw CocoaError(
        .fileNoSuchFile,
        userInfo: [
          NSFilePathErrorKey: Bundle.module.bundleURL.appendingPathComponent("artwork.plist").path
        ])
    }
    return try Self(data: Data(contentsOf: url))
  }
  public func url(subjectID: Int64) -> URL? {
    paths[subjectID].flatMap {
      URL(string: "https://global.discourse-cdn.com/wanikanicommunity/original/4X/\($0).png")
    }
  }
}
