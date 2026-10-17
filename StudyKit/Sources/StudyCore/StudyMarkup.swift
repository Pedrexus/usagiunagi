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
  private static let tags = try! NSRegularExpression(
    pattern:
      #"(<|\[)(/?)(radical|kanji|kan|vocabulary|reading|ja|jp|b|em|strong|i|a)(?:\s+href\s*=\s*["']([^"']*)["'][^>\]]*)?(>|\])"#,
    options: .caseInsensitive)

  public static func parse(_ source: String) -> [Run] {
    let text = source as NSString
    var stack: [Tag] = []
    var runs: [Run] = []
    var position = 0
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
    for match in tags.matches(in: source, range: NSRange(location: 0, length: text.length)) {
      append(
        text.substring(with: NSRange(location: position, length: match.range.location - position)))
      position = match.range.upperBound
      let opening = text.substring(with: match.range(at: 1))
      let closing = text.substring(with: match.range(at: 5))
      let name = text.substring(with: match.range(at: 3)).lowercased()
      guard (opening == "<" && closing == ">") || (opening == "[" && closing == "]") else {
        append(text.substring(with: match.range))
        continue
      }
      if text.substring(with: match.range(at: 2)) == "/" {
        guard stack.last?.name == name else {
          append(text.substring(with: match.range))
          continue
        }
        stack.removeLast()
      } else {
        let styles: [String: Style] = [
          "radical": .radical, "kanji": .kanji, "kan": .kanji,
          "vocabulary": .vocabulary, "reading": .reading, "ja": .japanese, "jp": .japanese,
          "b": .bold, "em": .bold, "strong": .bold, "i": .italic,
        ]
        let href =
          match.range(at: 4).location == NSNotFound ? nil : text.substring(with: match.range(at: 4))
        stack.append(Tag(name: name, style: styles[name], link: href.flatMap(webURL)))
      }
    }
    append(text.substring(from: position))
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
