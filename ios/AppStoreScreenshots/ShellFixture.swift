#if DEBUG
  import Foundation
  import PromiseKit

  final class ShellFixtureCachingClient: FakeLocalCachingClient {
    private var refreshing = false

    override func sync(quick: Bool, progress: Progress) -> PMKFinalizer {
      if quick || refreshing {
        progress.totalUnitCount = 1
        progress.completedUnitCount = 1
        return Promise.value(()).cauterize()
      }
      refreshing = true
      progress.totalUnitCount = 4
      return after(seconds: 4).map {
        progress.completedUnitCount = 1
      }.then { after(seconds: 4) }.map {
        progress.completedUnitCount = 3
      }.then { after(seconds: 8) }.ensure { [weak self] in
        progress.completedUnitCount = 4
        self?.refreshing = false
      }.cauterize()
    }
  }
#endif
