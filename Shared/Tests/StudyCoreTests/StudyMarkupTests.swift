import Foundation
import Testing

@testable import StudyCore

struct StudyMarkupTests {
  @Test(arguments: ["\u{301}かな", "か\u{3099}", "👩🏽‍💻"])
  func unicodeScalarsAdjacentToTagsRemainStyled(_ text: String) {
    let runs = StudyMarkup.parse("<b>\(text)</b>")
    #expect(runs.count == 1)
    #expect(runs.first?.text == text)
    #expect(runs.first?.styles == [.bold])
  }

  @Test func nestedMarkupPreservesStylesAndUnicode() {
    let runs = StudyMarkup.parse("  あ[ja]二[b]🐰[i]三[/i]四[/b]五[/ja]六\n")
    #expect(runs.map(\.text) == ["  あ", "二", "🐰", "三", "四", "五", "六\n"])
    #expect(
      runs.map(\.styles) == [
        [], [.japanese], [.japanese, .bold], [.japanese, .bold, .italic],
        [.japanese, .bold], [.japanese], [],
      ])
  }
  @Test func linksSurviveNestedStylesAndUnclosedFinalText() {
    let runs = StudyMarkup.parse(#"See <a href="/kanji/一"><b>one</b> more"#)
    #expect(runs.map(\.text) == ["See ", "one", " more"])
    #expect(runs[1].link?.absoluteString == "https://www.wanikani.com/kanji/%E4%B8%80")
    #expect(runs[2].link == runs[1].link)
    #expect(runs[1].styles == [.bold] && runs[2].styles.isEmpty)
  }
  @Test func malformedAndUnknownMarkupNeverLosesTextOrExecutes() {
    let source = "a<unknown>b</unknown><b]c[/i]d<script>alert(1)</script>"
    #expect(StudyMarkup.parse(source).map(\.text).joined() == source)
    #expect(StudyMarkup.parse("<b>one</i>two</b>").map(\.text).joined() == "one</i>two")
  }
  @Test(arguments: [
    "javascript:alert(1)", "data:text/html,test", "file:///tmp/example",
    "https://user:password@example.com", "",
  ])
  func unsafeLinksRemainPlainText(address: String) {
    let runs = StudyMarkup.parse("<a href=\"\(address)\">label</a>")
    #expect(runs.map(\.text).joined() == "label")
    #expect(runs.allSatisfy { $0.link == nil })
    #expect(StudyMarkup.webURL(address) == nil)
  }
  @Test func tagAliasesAndCaseMatchExistingMnemonicVocabulary() {
    let runs = StudyMarkup.parse(
      "<RADICAL>r</RADICAL><kan>k</kan><vocabulary>v</vocabulary><reading>x</reading><jp>j</jp><em>e</em><strong>s</strong>"
    )
    #expect(runs.map(\.text) == ["r", "k", "v", "x", "j", "es"])
    #expect(
      runs.map(\.styles) == [[.radical], [.kanji], [.vocabulary], [.reading], [.japanese], [.bold]])
  }
}
