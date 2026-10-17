import Foundation

/// Shared values; each host preserves its existing durable settings format.
public struct ReviewPreferences: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
    public enum StageIndicator: String, Codable, CaseIterable, Sendable { case none, name, dots }
    public var appearance = Appearance.system
    public var stageIndicator = StageIndicator.name
    public var fontScale = 1.0
    public var revealAnswers = true
    public var revealFullAnswer = false
    public var exactMatch = false
    public var allowCorrections = true
    public var allowSkipping = false
    public var autoplayAudio = false
    public var interruptBackgroundAudio = false
    public init() {}

    /// A settings window only replaces fields it changed, preserving another window's edits.
    public mutating func applyChanges(from old: Self, to new: Self) {
        if old.appearance != new.appearance { appearance = new.appearance }
        if old.stageIndicator != new.stageIndicator { stageIndicator = new.stageIndicator }
        if old.fontScale != new.fontScale { fontScale = new.fontScale }
        for key in [\Self.revealAnswers, \.revealFullAnswer, \.exactMatch, \.allowCorrections,
                    \.allowSkipping, \.autoplayAudio, \.interruptBackgroundAudio] {
            if old[keyPath: key] != new[keyPath: key] { self[keyPath: key] = new[keyPath: key] }
        }
    }
}
