import StudyCore
import StudyPersistence
import SwiftUI

struct MnemonicText: View {
  let source: String
  private var attributed: AttributedString {
    StudyMarkup.parse(source).reduce(into: AttributedString()) { result, run in
      var part = AttributedString(run.text)
      var font = Font.body
      if run.styles.contains(.bold) { font = font.bold() }
      if run.styles.contains(.italic) { font = font.italic() }
      part.font = font
      for style in run.styles {
        switch style {
        case .radical: part.foregroundColor = StudyPalette.radical
        case .kanji: part.foregroundColor = StudyPalette.kanji
        case .vocabulary: part.foregroundColor = StudyPalette.vocabulary
        case .reading: part.font = font.bold()
        default: break
        }
      }
      part.link = run.link
      result += part
    }
  }
  var body: some View {
    Text(attributed).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
  }
}

public struct NativeSubjectDetailsView: View {
  private let store: StudyStore
  private let accountID: String
  private let subjectID: Int64
  private let reviewQuestion: StudyQuestionKind?
  @State private var details: StudySubjectDetails?
  @State private var error: String?

  public init(
    store: StudyStore, accountID: String, subjectID: Int64, reviewQuestion: StudyQuestionKind? = nil
  ) {
    self.store = store
    self.accountID = accountID
    self.subjectID = subjectID
    self.reviewQuestion = reviewQuestion
  }
  public var body: some View {
    Group {
      if let details {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            if reviewQuestion == nil {
              if details.subject.japanese.isEmpty,
                let url = URL(string: details.subject.characterImageURL)
              {
                RadicalImageView(url: url).frame(height: 90)
              } else {
                Text(details.subject.japanese).font(.largeTitle)
              }
              Text("Level \(details.subject.level) · \(details.subject.kind.rawValue.capitalized)")
                .foregroundStyle(.secondary)
            }
            if reviewQuestion == .reading {
              readingDetails(details)
              meaningDetails(details)
            } else {
              meaningDetails(details)
              readingDetails(details)
            }
            if let names = details.subject.partOfSpeechNames, !names.isEmpty {
              section("Parts of speech") { Text(names.joined(separator: ", ")) }
            }
            if !details.subject.deprecatedMnemonic.isEmpty {
              DisclosureGroup("Earlier radical mnemonic") {
                MnemonicText(source: details.subject.deprecatedMnemonic)
              }
            }
            if !details.subject.sentences.isEmpty {
              section("Context sentences") {
                ForEach(Array(details.subject.sentences.enumerated()), id: \.offset) {
                  _, sentence in
                  VStack(alignment: .leading, spacing: 4) {
                    Text(sentence.japanese)
                    Text(sentence.english).foregroundStyle(.secondary)
                  }.padding(.vertical, 4)
                }
              }
            }
            related("Components", details.components)
            related("Found in", details.combinations)
            related("Similar kanji", details.similar)
            if details.unavailableRelatedCount > 0 {
              Text("Some related subjects are outside your saved catalog or content access.")
                .font(.caption).foregroundStyle(.secondary)
            }
            if !details.subject.visuallySimilarKanji.isEmpty {
              section("Other similar forms") { Text(details.subject.visuallySimilarKanji) }
            }
            if let url = StudyMarkup.webURL(details.subject.documentURL),
              url.host == "www.wanikani.com"
            {
              Link("Open on WaniKani", destination: url)
            }
          }.padding().textSelection(.enabled)
        }
      } else if let error {
        ContentUnavailableView(
          "Subject unavailable", systemImage: "book.closed", description: Text(error))
      } else {
        ProgressView("Loading saved subject")
      }
    }
    .task(id: [accountID, String(subjectID)]) {
      details = nil
      error = nil
      do {
        let value = try await store.subjectDetails(subjectID: subjectID, accountID: accountID)
        try Task.checkCancellation()
        details = value
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    .navigationDestination(for: Int64.self) { id in
      NativeSubjectDetailsView(store: store, accountID: accountID, subjectID: id).navigationTitle(
        "Related subject")
    }
  }
  @ViewBuilder private func meaningDetails(_ details: StudySubjectDetails) -> some View {
    section("Meanings") {
      Text(
        details.subject.meanings.filter { $0.role != .blacklist }.map(\.text).joined(
          separator: ", "))
      if let material = details.material, !material.meaningSynonyms.isEmpty {
        LabeledContent("Your synonyms", value: material.meaningSynonyms.joined(separator: ", "))
      }
    }
    mnemonic("Meaning mnemonic", details.subject.meaningMnemonic)
    mnemonic("Meaning hint", details.subject.meaningHint)
    note("Your meaning note", details.material?.meaningNote)
  }
  @ViewBuilder private func readingDetails(_ details: StudySubjectDetails) -> some View {
    if !details.subject.readings.isEmpty {
      section("Readings") {
        ForEach(Array(details.subject.readings.enumerated()), id: \.offset) { _, reading in
          LabeledContent(reading.kind.label) {
            Text(reading.text + (reading.isPrimary ? " · Primary" : ""))
              .fontWeight(reading.isPrimary ? .semibold : .regular)
          }
        }
      }
    }
    mnemonic("Reading mnemonic", details.subject.readingMnemonic)
    mnemonic("Reading hint", details.subject.readingHint)
    note("Your reading note", details.material?.readingNote)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  @ViewBuilder private func mnemonic(_ title: String, _ text: String) -> some View {
    if !text.isEmpty { section(title) { MnemonicText(source: text) } }
  }
  @ViewBuilder private func note(_ title: String, _ text: String?) -> some View {
    if let text, !text.isEmpty { section(title) { Text(text) } }
  }
  @ViewBuilder private func related(_ title: String, _ subjects: [CatalogSubject]) -> some View {
    if !subjects.isEmpty {
      section(title) {
        ForEach(subjects) { subject in
          NavigationLink(value: subject.id) {
            HStack {
              LabeledContent(
                subject.japanese.isEmpty ? subject.summary.meaning : subject.japanese,
                value: "Level \(subject.level) · \(subject.summary.meaning)")
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
    }
  }
}

extension CatalogSubject.Reading.Kind {
  fileprivate var label: String {
    switch self {
    case .unknown: "Reading"
    case .onyomi: "On’yomi"
    case .kunyomi: "Kun’yomi"
    case .nanori: "Nanori"
    }
  }
}
