import Foundation
import CoreText
import CoreGraphics

// Create outlined vector lettering; no font file is shipped in the app.
let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "Resources/UsagiUnagi.icon/Assets", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let font = CTFontCreateWithName("HiraginoSans-W7" as CFString, 1000, nil)
for (character, name, box, color) in [
    ("兔", "RabbitKanji", CGRect(x: 236, y: 152, width: 552, height: 332), "#315E70"),
    ("鰻", "EelKanji", CGRect(x: 236, y: 524, width: 552, height: 348), "#315E70")
] {
    var code = Array(character.utf16); var glyphs = [CGGlyph](repeating: 0, count: code.count)
    guard CTFontGetGlyphsForCharacters(font, &code, &glyphs, code.count),
          let raw = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { fatalError("Missing glyph: \(character)") }
    let b = raw.boundingBoxOfPath
    var transform = CGAffineTransform(a: box.width / b.width, b: 0, c: 0, d: -box.height / b.height,
                                     tx: box.minX - b.minX * box.width / b.width,
                                     ty: box.maxY + b.minY * box.height / b.height)
    let path = raw.copy(using: &transform)!
    var data = ""
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, p.y) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: data += "M" + point(e.points[0])
        case .addLineToPoint: data += "L" + point(e.points[0])
        case .addQuadCurveToPoint: data += "Q" + point(e.points[0]) + " " + point(e.points[1])
        case .addCurveToPoint: data += "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2])
        case .closeSubpath: data += "Z"
        @unknown default: fatalError("Unknown path element")
        }
    }
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\"><path fill=\"\(color)\" d=\"\(data)\"/></svg>\n"
    try svg.write(to: output.appending(path: name + ".svg"), atomically: true, encoding: .utf8)
}
