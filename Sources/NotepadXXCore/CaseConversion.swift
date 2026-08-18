import Foundation

/// Notepad++'s Edit > Convert Case To submenu.
public enum CaseConversion: String, CaseIterable, Sendable {
    case upper, lower, proper, properBlend, sentence, sentenceBlend, invert, random

    public var menuTitle: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .proper: return "Proper Case"
        case .properBlend: return "Proper Case (blend)"
        case .sentence: return "Sentence case"
        case .sentenceBlend: return "Sentence case (blend)"
        case .invert: return "iNVERT cASE"
        case .random: return "ranDOm CasE"
        }
    }

    /// `randomSource` is injectable so the random variant is testable.
    public func apply(to text: String, randomSource: () -> Bool = { Bool.random() }) -> String {
        switch self {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .proper: return Self.titleCase(text, blend: false)
        case .properBlend: return Self.titleCase(text, blend: true)
        case .sentence: return Self.sentenceCase(text, blend: false)
        case .sentenceBlend: return Self.sentenceCase(text, blend: true)
        case .invert: return Self.invertCase(text)
        case .random: return Self.randomCase(text, randomSource: randomSource)
        }
    }

    /// Upper-cases the first letter of each word. "Blend" leaves the remaining
    /// characters untouched rather than lower-casing them, which is what lets
    /// you fix "mcdonald" without destroying "McDonald".
    private static func titleCase(_ text: String, blend: Bool) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if character.isLetter || character.isNumber {
                if atWordStart {
                    result += character.uppercased()
                } else {
                    result += blend ? String(character) : character.lowercased()
                }
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    /// Upper-cases the first letter after each sentence terminator.
    private static func sentenceCase(_ text: String, blend: Bool) -> String {
        var result = ""
        var atSentenceStart = true
        for character in text {
            if character.isLetter {
                if atSentenceStart {
                    result += character.uppercased()
                    atSentenceStart = false
                } else {
                    result += blend ? String(character) : character.lowercased()
                }
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    atSentenceStart = true
                }
            }
        }
        return result
    }

    private static func invertCase(_ text: String) -> String {
        String(text.map { character in
            if character.isUppercase { return Character(character.lowercased()) }
            if character.isLowercase { return Character(character.uppercased()) }
            return character
        })
    }

    private static func randomCase(_ text: String, randomSource: () -> Bool) -> String {
        String(text.map { character in
            guard character.isLetter else { return character }
            return randomSource() ? Character(character.uppercased()) : Character(character.lowercased())
        })
    }
}
