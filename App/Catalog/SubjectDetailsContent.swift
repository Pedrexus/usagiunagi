import StudyCore
import SwiftUI

struct MnemonicText: View {
  let source: String
  @Environment(\.colorScheme) private var colorScheme
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
      if colorScheme == .dark, let color = part.foregroundColor {
        part.foregroundColor = color.mix(with: .white, by: 0.4)
      }
      part.link = run.link
      result += part
    }
  }
  var body: some View { Text(attributed).textSelection(.enabled) }
}

/// Saved values and actions are supplied by each host; this view never owns a storage writer.
struct SubjectDetailsContent: View {
  let subject: CatalogSubject
  let material: StudyMaterial?
  let assignment: CatalogAssignment?
  private static let artwork = try? StudyArtwork.bundled()
  let components: [CatalogSubject]
  let combinations: [CatalogSubject]
  let similar: [CatalogSubject]
  let preferences: SubjectDetailsPreferences
  let visibleQuestions: Set<StudyQuestionKind>
  let reviewQuestion: StudyQuestionKind?
  let edit: (() -> Void)?
  let openSubject: (Int64) -> Void
  let playAudio: (() -> Void)?
  let audioState: SubjectAudioState
  let audioError: String?

  private var visibility: SubjectDetailVisibility { SubjectDetailVisibility(visibleQuestions) }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 10) {
      if reviewQuestion == .reading {
        reading
        meaning
      } else {
        meaning
        reading
      }
      related(subject.kind == .kanji ? "Radicals" : "Kanji", components)
      if reviewQuestion == .reading {
        readingExplanation
        meaningExplanation
      } else {
        meaningExplanation
        readingExplanation
      }
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
    }.frame(maxWidth: 760).frame(maxWidth: .infinity).textSelection(.enabled)
  }
  private func contextSentenceText(_ sentence: CatalogSubject.Sentence) -> AttributedString {
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
        }
      }
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
    }
  }
  @ViewBuilder private var meaningExplanation: some View {
    if visibility.meaning {
      explanation(
        "Meaning explanation", text: subject.meaningMnemonic, hint: subject.meaningHint,
        note: material?.meaningNoteText, id: "meaning")
    }
  }
  @ViewBuilder private var readingExplanation: some View {
    if visibility.reading && visibility.readingExplanation {
      explanation(
        "Reading explanation", text: subject.readingMnemonic, hint: subject.readingHint,
        note: material?.readingNote, id: "reading")
    }
  }
  private func section<Content: View>(
    _ title: String, editMaterial: (() -> Void)? = nil, @ViewBuilder content: () -> Content
  )
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if let editMaterial {
          Button("Edit notes and synonyms", systemImage: "square.and.pencil", action: editMaterial)
            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("subject.editMaterial")
        }
      }
      VStack(alignment: .leading, spacing: 6, content: content)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
    }
  }
  @ViewBuilder private func explanation(
    _ title: String, text: String, hint: String, note: String?, id: String
  ) -> some View {
    if !text.isEmpty || !hint.isEmpty || !(note ?? "").isEmpty {
      section(title) {
        if !text.isEmpty { MnemonicText(source: text) }
        if !hint.isEmpty {
          if !text.isEmpty { Divider() }
          MnemonicText(source: hint).foregroundStyle(.secondary)
        }
        if let note, !note.isEmpty { LabeledContent("Your note") { Text(note) } }
      }.accessibilityIdentifier("subject.\(id)Explanation")
    }
  }
  @ViewBuilder private func related(_ title: String, _ subjects: [CatalogSubject]) -> some View {
    if !subjects.isEmpty {
      section(title) {
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(subjects) { subject in
              Button {
                openSubject(subject.id)
              } label: {
                HStack(spacing: 6) {
                  Group {
                    if subject.japanese.isEmpty, let url = URL(string: subject.characterImageURL),
                      !subject.characterImageURL.isEmpty
                    {
                      RadicalImageView(url: url).environment(\.colorScheme, .dark)
                        .frame(width: 28, height: 28)
                    } else {
                      Text(subject.japanese.isEmpty ? subject.summary.meaning : subject.japanese)
                        .font(.title3)
                    }
                  }.padding(6).frame(minWidth: 32, minHeight: 32).foregroundStyle(.white)
                    .background(StudyPalette.color(for: subject.kind), in: .rect(cornerRadius: 8))
                  Text(subject.summary.meaning).foregroundStyle(.primary)
                }.frame(minHeight: 44).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("subject.related.\(subject.id)")
                .accessibilityLabel(
                  "\(subject.japanese), \(subject.summary.meaning), Level \(subject.level)")
            }
          }
        }.scrollIndicators(.hidden)
      }
    }
  }
}

struct SubjectDetailsHeader: View {
  let subject: CatalogSubject
  var fontSize = 48.0
  @ScaledMetric(relativeTo: .largeTitle) private var scale = 1.0
  var body: some View {
    let size = fontSize * scale
    VStack(spacing: 4) {
      Group {
        if subject.japanese.isEmpty, let url = URL(string: subject.characterImageURL) {
          RadicalImageView(url: url).environment(\.colorScheme, .dark).frame(height: size)
        } else {
          Text(subject.japanese).font(.system(size: size))
        }
      }.accessibilityIdentifier("subject.characters")
      Text("\(subject.kind.rawValue.capitalized) · Level \(subject.level)").font(.caption)
    }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal)
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
