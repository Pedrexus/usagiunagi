extension StudyMarkResult {
  /// Only a completed, penalty-free item can reach a new category locally.
  /// WaniKani confirms the actual SRS stage after synchronization.
  public var estimatedMilestone: String? {
    guard subjectFinished, didLevelUp else { return nil }
    switch estimatedSRSStage {
    case 5: return "Guru"
    case 7: return "Master"
    case 8: return "Enlightened"
    case 9: return "Burned"
    default: return nil
    }
  }
}
