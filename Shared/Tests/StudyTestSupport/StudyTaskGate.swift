public actor StudyTaskGate {
  public init() {}
  private var entered = false
  private var cancelled = false
  private var entryWaiter: CheckedContinuation<Void, Never>?
  private var cancellationWaiter: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  public func pause() async {
    entered = true
    entryWaiter?.resume()
    entryWaiter = nil
    await withTaskCancellationHandler {
      await withCheckedContinuation { release = $0 }
    } onCancel: {
      Task { await self.sawCancellation() }
    }
  }
  private func sawCancellation() {
    cancelled = true
    cancellationWaiter?.resume()
    cancellationWaiter = nil
  }
  public func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiter = $0 } }
  }
  public func waitForCancellation() async {
    if !cancelled { await withCheckedContinuation { cancellationWaiter = $0 } }
  }
  public func resume() {
    release?.resume()
    release = nil
  }
}
