import Foundation

struct TranscriptFormatter {
    func format(
        transcript: String?,
        words: [DeepgramWord]
    ) -> String {
        let normalizedTranscript = normalizeText(transcript ?? "")

        if normalizedTranscript.isEmpty {
            return finalizeSentence(formatFromWords(words))
        }

        if containsPunctuation(normalizedTranscript) {
            return finalizeSentence(normalizedTranscript)
        }

        let wordBased = formatFromWords(words)
        if !wordBased.isEmpty, wordBased != normalizedTranscript {
            return finalizeSentence(wordBased)
        }

        return finalizeSentence(applyFallbackCommaBreaks(to: normalizedTranscript))
    }

    private func formatFromWords(_ words: [DeepgramWord]) -> String {
        guard !words.isEmpty else { return "" }

        var result = ""
        var previousEnd: Double?
        var insertedPunctuation = false

        for word in words {
            let token = normalizeToken(word.punctuatedWord ?? word.word)
            guard !token.isEmpty else { continue }

            if let previousEnd {
                let gap = word.start - previousEnd
                if gap >= 0.95 {
                    if !endsWithPunctuation(result) {
                        result.append(questionLike(result) ? "？" : "。")
                    }
                    insertedPunctuation = true
                } else if gap >= 0.45 {
                    if !endsWithPausePunctuation(result) {
                        result.append("，")
                    }
                    insertedPunctuation = true
                }
            }

            appendToken(token, to: &result)
            previousEnd = word.end
        }

        let cleaned = normalizeText(result)
        if insertedPunctuation {
            return cleaned
        }

        return applyFallbackCommaBreaks(to: cleaned)
    }

    private func appendToken(_ token: String, to text: inout String) {
        guard !token.isEmpty else { return }
        guard let last = text.last else {
            text.append(token)
            return
        }

        if shouldInsertSpace(between: last, and: token.first!) {
            text.append(" ")
        }
        text.append(token)
    }

    private func normalizeToken(_ token: String) -> String {
        normalizeText(token)
    }

    private func normalizeText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var output = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        output = replacingRegex(
            "(\\s)+",
            in: output,
            with: " "
        )
        output = replacingRegex(
            "(?<=[\\p{Han}])\\s+(?=[\\p{Han}])",
            in: output,
            with: ""
        )
        output = replacingRegex(
            "\\s*([，。！？；：,.!?;:])\\s*",
            in: output,
            with: "$1"
        )

        output = output
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: ".", with: "。")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "!", with: "！")
            .replacingOccurrences(of: ";", with: "；")
            .replacingOccurrences(of: ":", with: "：")

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyFallbackCommaBreaks(to text: String) -> String {
        guard !text.isEmpty else { return "" }
        guard !containsPunctuation(text) else { return text }

        let characters = Array(text)
        guard characters.count > 14 else { return text }

        var output = ""
        var currentCount = 0

        for (index, character) in characters.enumerated() {
            output.append(character)
            currentCount += 1

            let remaining = characters.count - index - 1
            if currentCount >= 14, remaining > 6 {
                output.append("，")
                currentCount = 0
            }
        }

        return output
    }

    private func finalizeSentence(_ text: String) -> String {
        let trimmed = normalizeText(text)
        guard !trimmed.isEmpty else { return "" }
        guard !endsWithPunctuation(trimmed) else { return trimmed }
        return trimmed + (questionLike(trimmed) ? "？" : "。")
    }

    private func containsPunctuation(_ text: String) -> Bool {
        text.range(of: "[，。！？；：,.!?;:]", options: .regularExpression) != nil
    }

    private func endsWithPunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "，。！？；：,.!?;:".contains(last)
    }

    private func endsWithPausePunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "，；：,;:".contains(last)
    }

    private func questionLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hints = ["吗", "呢", "么", "是否", "为什么", "为何", "怎么", "如何", "能不能", "可不可以", "是不是", "要不要"]
        if hints.contains(where: { trimmed.hasSuffix($0) }) {
            return true
        }
        if hints.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        return false
    }

    private func shouldInsertSpace(between left: Character, and right: Character) -> Bool {
        isASCIIWordCharacter(left) && isASCIIWordCharacter(right)
    }

    private func isASCIIWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }

    private func replacingRegex(
        _ pattern: String,
        in text: String,
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

struct DeepgramWord: Decodable {
    let word: String
    let punctuatedWord: String?
    let start: Double
    let end: Double

    enum CodingKeys: String, CodingKey {
        case word
        case punctuatedWord = "punctuated_word"
        case start
        case end
    }
}
