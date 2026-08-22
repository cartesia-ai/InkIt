import SwiftUI

enum SpeakerColor {
    private static let prefix = "Speaker "

    static func forLabel(_ label: String) -> Color {
        if label == "You" || label == "Me" { return .speakerYou }
        guard label.hasPrefix(prefix), let n = Int(label.dropFirst(prefix.count)), n >= 1 else {
            return Color.inkSub
        }
        return Color.speakerPalette[(n - 1) % Color.speakerPalette.count]
    }
}


private enum NameCandidateHighlighting {
    private static let sentenceStarters: Set<String> = [
        "The", "This", "That", "These", "Those", "It", "I", "We", "They", "He", "She", "You",
        "A", "An", "In", "On", "At", "For", "With", "After", "Before", "During", "As", "If",
        "When", "While", "Because", "So", "But", "And", "Or", "Also", "However", "Next", "Then",
        "Action", "Items", "Summary", "Overview", "Notes", "Meeting", "No"
    ]

    static func candidateRanges(
        in attributed: AttributedString,
        excluding matchedRanges: [Range<AttributedString.Index>]
    ) -> [Range<AttributedString.Index>] {
        var candidates: [Range<AttributedString.Index>] = []
        var isSentenceStart = true
        var index = attributed.startIndex

        while index < attributed.endIndex {
            while index < attributed.endIndex, attributed.characters[index] == " " {
                index = attributed.index(afterCharacter: index)
            }
            guard index < attributed.endIndex else { break }

            var wordEnd = index
            while wordEnd < attributed.endIndex, attributed.characters[wordEnd] != " " {
                wordEnd = attributed.index(afterCharacter: wordEnd)
            }

            let startsSentence = isSentenceStart
            let lastChar = attributed.characters[attributed.index(beforeCharacter: wordEnd)]
            isSentenceStart = lastChar == "." || lastChar == "!" || lastChar == "?"

            var trimmedStart = index
            while trimmedStart < wordEnd,
                  !(attributed.characters[trimmedStart].isLetter || attributed.characters[trimmedStart].isNumber) {
                trimmedStart = attributed.index(afterCharacter: trimmedStart)
            }
            var trimmedEnd = wordEnd
            while trimmedEnd > trimmedStart {
                let before = attributed.index(beforeCharacter: trimmedEnd)
                if attributed.characters[before].isLetter || attributed.characters[before].isNumber { break }
                trimmedEnd = before
            }

            if trimmedStart < trimmedEnd, !startsSentence {
                let range = trimmedStart..<trimmedEnd
                let trimmed = String(attributed.characters[range])
                if let first = trimmed.first, first.isUppercase,
                   trimmed.dropFirst().contains(where: { $0.isLowercase }),
                   !sentenceStarters.contains(trimmed),
                   !matchedRanges.contains(where: { $0.overlaps(range) }) {
                    candidates.append(range)
                }
            }

            index = wordEnd
        }

        return candidates
    }
}

enum SummaryRendering {
    static func text(_ summary: String, speakerLabels: [String], boldUnregisteredNames: Bool = false) -> Text {
        guard var attributed = try? AttributedString(markdown: summary) else {
            return Text(summary)
        }
        let matchedRanges = colorSpeakerMentions(in: &attributed, labels: speakerLabels)
        if boldUnregisteredNames {
            for range in NameCandidateHighlighting.candidateRanges(in: attributed, excluding: matchedRanges) {
                attributed[range].font = .inkBodyEmphasized
            }
        }
        return Text(attributed)
    }

    private static func colorSpeakerMentions(
        in attributed: inout AttributedString,
        labels: [String]
    ) -> [Range<AttributedString.Index>] {
        var matched: [Range<AttributedString.Index>] = []
        for label in labels {
            matched.append(contentsOf: highlightWholeWord(label, in: &attributed))
        }
        return matched
    }

    private static func highlightWholeWord(_ word: String, in attributed: inout AttributedString) -> [Range<AttributedString.Index>] {
        var matched: [Range<AttributedString.Index>] = []
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: word) {
            if isWholeWord(range, in: attributed) {
                attributed[range].foregroundColor = SpeakerColor.forLabel(word)
                matched.append(range)
            }
            searchStart = range.upperBound
        }
        return matched
    }

    private static func isWholeWord(_ range: Range<AttributedString.Index>, in attributed: AttributedString) -> Bool {
        if range.lowerBound > attributed.startIndex {
            let before = attributed.index(beforeCharacter: range.lowerBound)
            if attributed.characters[before].isLetter || attributed.characters[before].isNumber { return false }
        }
        if range.upperBound < attributed.endIndex,
           attributed.characters[range.upperBound].isLetter || attributed.characters[range.upperBound].isNumber {
            return false
        }
        return true
    }
}
