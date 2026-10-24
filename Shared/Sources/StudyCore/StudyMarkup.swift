import Foundation

/// WaniKani's small mnemonic vocabulary, parsed as text rather than executable HTML.
public enum StudyMarkup {
  public enum Style: String, Sendable {
    case radical, kanji, vocabulary, reading, japanese, bold, italic
  }
  public struct Run: Equatable, Sendable {
    public var text: String
    public let styles: [Style]
    public let link: URL?
  }
  private struct Tag {
    let name: String
    let style: Style?
    let link: URL?
  }
  public static func parse(_ source: String) -> [Run] {
    let tags =
      #/
      (<|\[)(/?)(radical|kanji|kan|vocabulary|reading|ja|jp|b|em|strong|i|a)
      (?:\s+href\s*=\s*["']([^"']*)["'][^>\]]*)?(>|\])
      /#.ignoresCase().matchingSemantics(.unicodeScalar)
    var stack: [Tag] = []
    var runs: [Run] = []
    var position = source.startIndex
    func append(_ value: String) {
      guard !value.isEmpty else { return }
      let styles = stack.compactMap(\.style)
      let link = stack.last(where: { $0.name == "a" })?.link
      if let last = runs.last, last.styles == styles, last.link == link {
        runs[runs.count - 1].text += value
      } else {
        runs.append(Run(text: value, styles: styles, link: link))
      }
    }
    for match in source.matches(of: tags) {
      append(String(source[position..<match.range.lowerBound]))
      position = match.range.upperBound
      let (raw, opening, slash, tag, href, closing) = match.output
      let name = tag.lowercased()
      guard (opening == "<" && closing == ">") || (opening == "[" && closing == "]") else {
        append(String(raw))
        continue
      }
      if slash == "/" {
        guard stack.last?.name == name else {
          append(String(raw))
          continue
        }
        stack.removeLast()
      } else {
        let styles: [String: Style] = [
          "radical": .radical, "kanji": .kanji, "kan": .kanji,
          "vocabulary": .vocabulary, "reading": .reading, "ja": .japanese, "jp": .japanese,
          "b": .bold, "em": .bold, "strong": .bold, "i": .italic,
        ]
        stack.append(
          Tag(name: name, style: styles[name], link: href.map(String.init).flatMap(webURL)))
      }
    }
    append(String(source[position...]))
    return runs
  }

  public static func webURL(_ value: String) -> URL? {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let url = URL(string: value, relativeTo: URL(string: "https://www.wanikani.com/"))?
        .absoluteURL,
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
      url.user == nil, url.password == nil
    else { return nil }
    return url
  }
}
