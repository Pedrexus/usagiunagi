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

import Observation
import StudyCore
import StudyUI
import SwiftUI
import WaniKaniAPI

/// Temporary iOS boundary: rendering is shared SwiftUI; the existing cache remains the writer.
@MainActor @Observable final class LegacySubjectDetailsModel {
  private let services: TKMServices
  private let client: LocalCachingClient
  private let account: String?
  private weak var delegate: SubjectDelegate?
  private var original: TKMSubject?
  var subject: CatalogSubject?
  var material: StudyMaterial?
  var assignment: TKMAssignment?
  var components: [CatalogSubject] = []
  var combinations: [CatalogSubject] = []
  var similar: [CatalogSubject] = []
  var questions: Set<StudyQuestionKind> = [.meaning, .reading]
  var reviewQuestion: StudyQuestionKind?
  var presentationID = UUID()
  var audioState: SubjectAudioState { subject.map { services.audio.state(for: $0.id) } ?? .idle }
  var audioError: String? { subject.flatMap { services.audio.error(for: $0.id) } }
  var error: String?
  var fullAnswerPrompt = false
  private static var showAllCount = 0

  init(services: TKMServices, delegate: SubjectDelegate) {
    let client = services.localCachingClient!
    self.services = services
    self.client = client
    self.account = client.getUserInfo()?.username
    self.delegate = delegate
  }
  var preferences: SubjectDetailsPreferences {
    var value = SubjectDetailsPreferences()
    value.primaryKanjiReadingsOnly = !Settings.showAllReadings
    value.useKatakanaForOnyomi = Settings.useKatakanaForOnyomi
    value.showDeprecatedMnemonic = Settings.showOldMnemonic
    value.blurTranslations = Settings.blurContextSentences
    return value
  }
  var cachedImage: Image? {
    guard let subject, subject.hasCharacterImageFile,
      let image = UIImage(contentsOfFile: RadicalCharacterImages.pathForSubjectId(subject.id))
    else { return nil }
    return Image(uiImage: image).renderingMode(.template)
  }
  var canPlayAudio: Bool { !(subject?.audio.isEmpty ?? true) }
  var excluded: Bool { material?.isExcluded == true }
  var showsOptions: Bool {
    reviewQuestion == nil && subject?.kind == .vocabulary && Settings.allowExcludeItems
  }
  var artworkURL: URL? {
    guard Settings.showArtwork, services.reachability.isReachable(), let subject else { return nil }
    return ArtworkManager.artworkFullURL(subjectID: subject.id).flatMap(URL.init(string:))
  }
  private func checkAccount() throws {
    guard services.localCachingClient === client, let account, !account.isEmpty,
      client.getUserInfo()?.username == account
    else { throw DetailsError.accountChanged }
  }
  func update(
    subject: TKMSubject, assignment: TKMAssignment?, task: ReviewItem? = nil,
    reviewQuestion: StudyQuestionKind? = nil, material: TKMStudyMaterials? = nil
  ) {
    if FeatureFlags.dumpSubjectTextproto { print(subject) }
    self.original = subject
    self.assignment = assignment
    self.reviewQuestion = reviewQuestion
    questions = []
    if task == nil || task?.answeredMeaning == true || task?.answer.meaningWrong == true {
      questions.insert(.meaning)
    }
    if task == nil || task?.answeredReading == true || task?.answer.readingWrong == true {
      questions.insert(.reading)
    }
    presentationID = UUID()
    error = nil
    do {
      try checkAccount()
      var catalog = try LegacyStudyImporter.catalogSubject(subject)
      let level = client.getUserInfo()?.currentLevel ?? 0
      func related(_ ids: [Int64]) -> [CatalogSubject] {
        var seen: Set<Int64> = []
        return ids.filter { seen.insert($0).inserted }.compactMap { client.getSubject(id: $0) }
          .compactMap { try? LegacyStudyImporter.catalogSubject($0) }
      }
      components = related(subject.componentSubjectIds)
      combinations = related(subject.amalgamationSubjectIds).sorted { $0.level < $1.level }
      var similarIDs = subject.kanji.visuallySimilarKanjiIds
      for character in subject.kanji.visuallySimilarKanji {
        if let other = client.getSubject(japanese: String(character), type: .kanji) {
          similarIDs.append(other.id)
        }
      }
      similar = related(similarIDs).filter {
        Settings.showSimilarKanjiAboveLevel || $0.level <= level
      }
      // The legacy setting applies to every similar form, including supplementary characters.
      catalog.visuallySimilarKanji = ""
      catalog.visuallySimilarKanjiIDs = similar.map(\.id)
      self.subject = catalog
      if let material {
        self.material = StudyMaterial(
          subjectID: subject.id, meaningNote: material.meaningNote,
          readingNote: material.readingNote, meaningSynonyms: material.meaningSynonyms)
      } else {
        self.material = try editableMaterial().material
      }
    } catch {
      self.subject = nil
      self.error = error.localizedDescription
    }
  }
  func editableMaterial() throws -> StudyMaterialEdit<Int64> {
    try checkAccount()
    guard let subject, let account else { throw DetailsError.unavailable }
    guard let edit = client.editableStudyMaterial(subjectID: subject.id, account: account) else {
      throw DetailsError.accountChanged
    }
    return edit
  }
  func reload() {
    guard let original else { return }
    update(subject: original, assignment: client.getAssignment(subjectId: original.id))
  }
  func save(_ draft: StudyMaterial, version: Int64?) throws {
    try checkAccount()
    guard draft.subjectID == subject?.id, let account else { throw DetailsError.unavailable }
    guard client.saveEditedStudyMaterial(draft, expectedRevision: version, account: account) else {
      let current = try editableMaterial()
      throw StudyMaterialEditConflict(current: current)
    }
    material = try editableMaterial().material
  }
  func setExcluded(_ excluded: Bool) {
    do {
      let current = try editableMaterial()
      var draft = current.material
      draft.meaningNote =
        excluded
        ? draft.meaningNoteText + StudyMaterial.exclusionMarker : draft.meaningNoteText
      try save(draft, version: current.version)
    } catch { self.error = error.localizedDescription }
  }
  func openSubject(_ id: Int64) {
    guard let subject = client.getSubject(id: id) else { return }
    delegate?.didTapSubject(subject)
  }
  func openPractice() { if let original { delegate?.openPracticeReview(original) } }
  func showAllFields() {
    guard questions != [.meaning, .reading] else { return }
    questions = [.meaning, .reading]
    if !Settings.seenFullAnswerPrompt {
      Self.showAllCount += 1
      if Self.showAllCount >= 10 {
        Settings.seenFullAnswerPrompt = true
        fullAnswerPrompt = true
      }
    }
  }
  func playAudio() {
    guard canPlayAudio, let subject else { return }
    services.audio.toggle(
      subject: subject, interruptBackgroundAudio: Settings.interruptBackgroundAudio)
  }
  func sentenceText(_ sentence: CatalogSubject.Sentence) -> AttributedString {
    let text = NSAttributedString(string: sentence.japanese)
    guard let original else { return AttributedString(text) }
    return AttributedString(highlightOccurrences(of: original, in: text) ?? text)
  }
  private enum DetailsError: Error, LocalizedError {
    case accountChanged, unavailable
    var errorDescription: String? {
      switch self {
      case .accountChanged:
        "The account changed. Close these details and reopen the subject before editing."
      case .unavailable: "This subject is not in your saved catalog. Refresh study content."
      }
    }
  }
}

@MainActor struct SubjectDetailsPage: View {
  @Bindable var model: LegacySubjectDetailsModel
  var showsHeader = false
  var back: (() -> Void)?
  @State private var editing: EditRequest?
  private struct EditRequest: Identifiable {
    let id = UUID()
    let subject: CatalogSubject
    let initial: StudyMaterialEdit<Int64>
    let questions: Set<StudyQuestionKind>
  }
  var body: some View {
    ScrollView {
      if let subject = model.subject {
        VStack(alignment: .leading, spacing: 16) {
          if showsHeader {
            SubjectDetailsHeader(
              subject: subject, japaneseFont: TKMStyle.japaneseFontName,
              fontSize: TKMStyle.reviewSubjectFontSize() * 0.8, image: model.cachedImage)
          }
          SubjectDetailsContent(
            subject: subject, material: model.material, components: model.components,
            combinations: model.combinations, similar: model.similar,
            preferences: model.preferences,
            visibleQuestions: model.questions, reviewQuestion: model.reviewQuestion,
            edit: {
              do {
                editing = EditRequest(
                  subject: subject, initial: try model.editableMaterial(),
                  questions: SubjectDetailVisibility(model.questions).editableQuestions)
              } catch { model.error = error.localizedDescription }
            }, openSubject: { model.openSubject($0) },
            playAudio: model.canPlayAudio ? { model.playAudio() } : nil,
            audioState: model.audioState, audioError: model.audioError,
            sentenceText: { model.sentenceText($0) }
          ).padding(.horizontal)
          extras(subject).padding(.horizontal)
          if let error = model.error { Text(error).foregroundStyle(.red).padding() }
        }.padding(.bottom)
      } else {
        ContentUnavailableView(
          "Subject unavailable", systemImage: "book.closed",
          description: Text(model.error ?? "Refresh study content."))
      }
    }
    .defaultScrollAnchor(.top).id(model.presentationID)
    .accessibilityIdentifier("subject.scroll")
    .background(.background)
    .overlay(alignment: .topLeading) {
      if let back {
        Button("Back", systemImage: "chevron.backward", action: back).buttonStyle(.bordered)
          .accessibilityIdentifier("subject.back")
          .background(.regularMaterial, in: Capsule()).padding(8)
      }
    }
    .sheet(item: $editing) { request in
      StudyMaterialEditor(
        subject: request.subject, initial: request.initial, visibleQuestions: request.questions,
        saveMessage: "Saved on this device; uploads when online.",
        save: { draft, version in try model.save(draft, version: version) })
    }
    .confirmationDialog(
      "Always show the full answer?", isPresented: $model.fullAnswerPrompt,
      titleVisibility: .visible
    ) {
      Button("Always show") { Settings.showFullAnswer = true }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can change this in review settings at any time.")
    }
  }
  @ViewBuilder private func extras(_ subject: CatalogSubject) -> some View {
    if Settings.showStatsSection, let assignment = model.assignment {
      GroupBox("Stats") {
        VStack(spacing: 10) {
          LabeledContent("WaniKani level", value: String(subject.level))
          if assignment.hasStartedAt {
            if assignment.hasSrsStageNumber {
              LabeledContent("SRS stage", value: assignment.srsStage.description)
            }
            LabeledContent(
              "Started",
              value: assignment.startedAtDate.formatted(date: .abbreviated, time: .shortened))
            if assignment.hasAvailableAt {
              LabeledContent(
                "Next review",
                value: assignment.availableAtDate.formatted(date: .abbreviated, time: .shortened))
            }
            if assignment.hasPassedAt {
              LabeledContent(
                "Passed",
                value: assignment.passedAtDate.formatted(date: .abbreviated, time: .shortened))
            }
            if assignment.hasBurnedAt {
              LabeledContent(
                "Burned",
                value: assignment.burnedAtDate.formatted(date: .abbreviated, time: .shortened))
            }
          }
        }
      }
    }
    if let url = model.artworkURL {
      GroupBox("Artwork by @AmandaBear") { SubjectArtwork(url: url) }
    }
    if model.showsOptions {
      GroupBox {
        Toggle("Exclude this item", isOn: Binding(get: { model.excluded }, set: model.setExcluded))
          .accessibilityIdentifier("subject.excluded")
        Text("Excluded items do not appear in lessons or reviews.").font(.caption).foregroundStyle(
          .secondary)
      }
    }
    if FeatureFlags.showSubjectDeveloperOptions {
      Button("Open practice review", action: model.openPractice)
    }
  }
}
