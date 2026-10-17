// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import UIKit

class ArtworkModelItem: TableModelItem {
  let subjectID: Int64

  init(subjectID: Int64) {
    self.subjectID = subjectID
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: ArtworkModelCell.self)
  }
}

@MainActor
class ArtworkModelCell: TableModelCell {
  @TypedModelItem var item: ArtworkModelItem

  override func update() {
    let url = ArtworkManager.artworkFullURL(subjectID: item.subjectID).flatMap(URL.init(string:))
    contentConfiguration = UIHostingConfiguration {
      SubjectArtwork(url: url)
    }
  }
}

/// The cell supplies the available width, including in resized iPad windows.
private struct SubjectArtwork: View {
  let url: URL?

  var body: some View {
    if let url {
      AsyncImage(request: URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)) { phase in
        switch phase {
        case .empty:
          ProgressView()
        case let .success(image):
          image.resizable().scaledToFit().accessibilityLabel("Subject artwork")
        case .failure:
          Label("Error loading image", systemImage: "photo.badge.exclamationmark")
        @unknown default:
          EmptyView()
        }
      }
      .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
    } else {
      ContentUnavailableView("Artwork unavailable", systemImage: "photo")
    }
  }
}
