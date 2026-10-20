import StudyCore
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
  var body: some View { Text(attributed).textSelection(.enabled) }
}

/// Saved values and actions are supplied by each host; this view never owns a storage writer.
public struct SubjectDetailsContent: View {
  private let subject: CatalogSubject
  private let material: StudyMaterial?
  private let assignment: CatalogAssignment?
  private static let artwork = try? StudyArtwork.bundled()
  private let components: [CatalogSubject]
  private let combinations: [CatalogSubject]
  private let similar: [CatalogSubject]
  private let preferences: SubjectDetailsPreferences
  private let visibility: SubjectDetailVisibility
  private let reviewQuestion: StudyQuestionKind?
  private let edit: (() -> Void)?
  private let openSubject: (Int64) -> Void
  private let playAudio: (() -> Void)?
  private let audioState: SubjectAudioState
  private let audioError: String?
  private let sentenceText: ((CatalogSubject.Sentence) -> AttributedString)?

  public init(
    subject: CatalogSubject, material: StudyMaterial? = nil, assignment: CatalogAssignment? = nil,
    components: [CatalogSubject] = [], combinations: [CatalogSubject] = [],
    similar: [CatalogSubject] = [],
    preferences: SubjectDetailsPreferences = .init(),
    visibleQuestions: Set<StudyQuestionKind> = [.meaning, .reading],
    reviewQuestion: StudyQuestionKind? = nil, edit: (() -> Void)? = nil,
    openSubject: @escaping (Int64) -> Void, playAudio: (() -> Void)? = nil,
    audioState: SubjectAudioState = .idle, audioError: String? = nil,
    sentenceText: ((CatalogSubject.Sentence) -> AttributedString)? = nil
  ) {
    self.subject = subject
    self.material = material
    self.assignment = assignment
    self.components = components
    self.combinations = combinations
    self.similar = similar
    self.preferences = preferences
    self.visibility = SubjectDetailVisibility(visibleQuestions)
    self.reviewQuestion = reviewQuestion
    self.edit = edit
    self.openSubject = openSubject
    self.playAudio = playAudio
    self.audioState = audioState
    self.audioError = audioError
    self.sentenceText = sentenceText
  }
  public var body: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      if reviewQuestion == .reading {
        reading
        meaning
      } else {
        meaning
        reading
      }
      related(subject.kind == .kanji ? "Radicals" : "Kanji", components)
      if let names = subject.partOfSpeechNames, !names.isEmpty {
        section("Part of speech") { Text(names.joined(separator: ", ")) }
      }
      if visibility.meaning, preferences.showDeprecatedMnemonic, !subject.deprecatedMnemonic.isEmpty
      {
        DisclosureGroup("Earlier radical mnemonic") {
          MnemonicText(source: subject.deprecatedMnemonic)
        }
      }
      if visibility.meaning, !subject.sentences.isEmpty {
        section("Context sentences") {
          ForEach(Array(subject.sentences.enumerated()), id: \.offset) { index, sentence in
            ContextSentence(
              sentence: sentence, text: contextSentenceText(sentence),
              blurTranslation: preferences.blurTranslations, index: index)
          }
        }
      }
      related("Visually similar kanji", similar)
      related("Used in", combinations)
      if !subject.visuallySimilarKanji.isEmpty {
        section("Other similar forms") { Text(subject.visuallySimilarKanji) }
      }
      if preferences.showStatistics, let assignment {
        SubjectProgressView(assignment: assignment, level: subject.level)
      }
      if visibility.meaning, preferences.showArtwork {
        if let artwork = Self.artwork {
          if let url = artwork.url(subjectID: subject.id) {
            GroupBox("Artwork by @AmandaBear") { SubjectArtwork(url: url) }.accessibilityIdentifier(
              "subject.artwork")
          }
        } else {
          Label("Artwork catalog unavailable", systemImage: "photo.badge.exclamationmark")
        }
      }
      if let url = StudyMarkup.webURL(subject.documentURL), url.host == "www.wanikani.com" {
        Link("Open on WaniKani", destination: url)
      }
    }.textSelection(.enabled)
  }
  private func contextSentenceText(_ sentence: CatalogSubject.Sentence) -> AttributedString {
    if let sentenceText { return sentenceText(sentence) }
    let source = sentence.japanese
    var result = AttributedString()
    var cursor = source.startIndex
    for range in VocabularyHighlighter.ranges(of: subject, in: source) {
      result += AttributedString(source[cursor..<range.lowerBound])
      var highlighted = AttributedString(source[range])
      highlighted.foregroundColor = .red
      result += highlighted
      cursor = range.upperBound
    }
    result += AttributedString(source[cursor...])
    return result
  }
  @ViewBuilder private var meaning: some View {
    if visibility.meaning {
      section("Meaning", editMaterial: edit) {
        Text(
          subject.displayedMeanings(preferences: preferences).map(\.text).joined(separator: ", ")
        )
        .accessibilityIdentifier("subject.meanings")
        if let material, !material.meaningSynonyms.isEmpty {
          LabeledContent("Your synonyms", value: material.meaningSynonyms.joined(separator: ", "))
            .foregroundStyle(StudyPalette.radical)
        }
      }
      explanation(
        "Meaning explanation", text: subject.meaningMnemonic, hint: subject.meaningHint,
        note: material?.meaningNoteText, id: "meaning")
    }
  }
  @ViewBuilder private var reading: some View {
    if visibility.reading {
      let readings = subject.displayedReadings(preferences: preferences)
      if !readings.isEmpty {
        section("Reading") {
          ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
            LabeledContent(reading.kind.label) {
              Text(reading.text + (reading.isPrimary && readings.count > 1 ? " · Primary" : ""))
                .fontWeight(reading.isPrimary ? .semibold : .regular)
                .accessibilityIdentifier("subject.reading.\(index)")
            }
          }
          if let playAudio {
            Button(
              audioState == .loading
                ? "Cancel loading" : audioState == .playing ? "Stop reading" : "Play reading",
              systemImage: audioState == .playing ? "stop.fill" : "speaker.wave.2",
              action: playAudio
            )
            .keyboardShortcut("j", modifiers: []).accessibilityIdentifier("subject.audio")
            if audioState == .loading { ProgressView("Loading audio") }
            if let audioError {
              Text(audioError).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier(
                "subject.audioError")
            }
          }
        }
      }
      if visibility.readingExplanation {
        explanation(
          "Reading explanation", text: subject.readingMnemonic, hint: subject.readingHint,
          note: material?.readingNote, id: "reading")
      }
    }
  }
  private func section<Content: View>(
    _ title: String, editMaterial: (() -> Void)? = nil, @ViewBuilder content: () -> Content
  )
    -> some View
  {
    GroupBox {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 10, content: content).frame(
          maxWidth: .infinity, alignment: .leading)
        if let editMaterial {
          Button("Edit notes and synonyms", systemImage: "square.and.pencil", action: editMaterial)
            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("subject.editMaterial")
        }
      }
    } label: {
      Text(title).accessibilityAddTraits(.isHeader)
    }
  }
  @ViewBuilder private func explanation(
    _ title: String, text: String, hint: String, note: String?, id: String
  ) -> some View {
    if !text.isEmpty || !hint.isEmpty || !(note ?? "").isEmpty {
      section(title) {
        if !text.isEmpty { MnemonicText(source: text) }
        if !hint.isEmpty { MnemonicText(source: hint).foregroundStyle(.secondary) }
        if let note, !note.isEmpty { LabeledContent("Your note") { Text(note) } }
      }.accessibilityIdentifier("subject.\(id)Explanation")
    }
  }
  @ViewBuilder private func related(_ title: String, _ subjects: [CatalogSubject]) -> some View {
    if !subjects.isEmpty {
      section(title) {
        ForEach(subjects) { subject in
          Button {
            openSubject(subject.id)
          } label: {
            HStack {
              Text(subject.japanese.isEmpty ? subject.summary.meaning : subject.japanese)
                .font(.title3).foregroundStyle(StudyPalette.color(for: subject.kind))
              Text(subject.summary.meaning).foregroundStyle(.primary)
              Spacer()
              Text("Level \(subject.level)").font(.caption).foregroundStyle(.secondary)
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.frame(minHeight: 44).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityIdentifier("subject.related.\(subject.id)")
        }
      }
    }
  }
}

public struct SubjectDetailsHeader: View {
  private let subject: CatalogSubject
  private let japaneseFont: String?
  private let fontSize: Double
  private let image: Image?
  public init(
    subject: CatalogSubject, japaneseFont: String? = nil, fontSize: Double = 72, image: Image? = nil
  ) {
    self.subject = subject
    self.japaneseFont = japaneseFont
    self.fontSize = fontSize
    self.image = image
  }
  public var body: some View {
    VStack(spacing: 12) {
      Group {
        if let image {
          image.resizable().scaledToFit().frame(height: fontSize)
        } else if subject.japanese.isEmpty, let url = URL(string: subject.characterImageURL) {
          RadicalImageView(url: url).environment(\.colorScheme, .dark).frame(height: fontSize)
        } else {
          Text(subject.japanese).font(
            japaneseFont.map { .custom($0, size: fontSize) } ?? .system(size: fontSize)
          ).lineLimit(1).minimumScaleFactor(0.4)
        }
      }.accessibilityIdentifier("subject.characters")
      Text(subject.summary.meaning).font(.title2.bold())
      Text("\(subject.kind.rawValue.capitalized) · Level \(subject.level)").font(.subheadline)
    }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal)
      .background(StudyPalette.color(for: subject.kind))
  }
}

private struct ContextSentence: View {
  let sentence: CatalogSubject.Sentence
  let text: AttributedString
  let blurTranslation: Bool
  let index: Int
  @State private var revealed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text)
      if blurTranslation && !revealed {
        Button("Show translation", systemImage: "eye") { revealed = true }
          .buttonStyle(.bordered).controlSize(.large)
          .accessibilityIdentifier("subject.translation.\(index)")
      } else {
        Text(sentence.english).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 6)
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
