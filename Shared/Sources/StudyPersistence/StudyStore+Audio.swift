import StudyCore

extension StudyStore {
  public func audioCatalog(accountID: String) throws -> StudyAudioCatalog {
    try requireAccount(accountID)
    guard let account = try accountState(accountID: accountID) else {
      throw NativeReviewError.unavailableAccount
    }
    let subjects = try catalog(accountID: accountID).filter {
      $0.hiddenAt == nil && $0.id > 0 && $0.level <= account.profile.maxLevelGranted
    }
    return StudyAudioCatalog(
      accountID: accountID, currentLevel: account.profile.level,
      maximumLevel: account.profile.maxLevelGranted, voices: account.voices,
      audio: subjects.flatMap { subject in
        subject.audio.map {
          StudyAudioReference(
            subjectID: subject.id, voiceActorID: $0.voiceActorID, level: subject.level, url: $0.url)
        }
      })
  }
}
