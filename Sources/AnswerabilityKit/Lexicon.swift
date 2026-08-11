import Foundation

/// Every rule the kit uses to read English, stated in the open.
///
/// Deliberately not `NaturalLanguage`: a tagger's output moves with the OS version,
/// which would make a refusal reproducible on one machine and not another. A gate
/// whose answer depends on the host it runs on is not a gate anyone can rely on.
enum Lexicon {
    /// Words carrying no information need of their own.
    static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "have", "has", "had", "will", "would", "shall",
        "should", "can", "could", "may", "might", "must", "of", "to", "and",
        "or", "but", "if", "then", "than", "that", "this", "these", "those",
        "it", "its", "we", "you", "they", "them", "there", "here", "at", "by",
        "on", "as", "so", "such", "any", "all", "some", "our", "their", "get",
        "got", "about", "with", "from", "into", "over", "up", "out", "not",
        "many", "much", "for"
    ]

    /// Words that flip the direction of the sentence they appear in.
    ///
    /// `not` is a stop word *and* a negation cue: it carries no information need
    /// when read from a question, and reverses meaning when read from evidence.
    static let negationCues: Set<String> = [
        "not", "no", "never", "none", "neither", "nor", "cannot", "cant",
        "isnt", "arent", "wasnt", "werent", "doesnt", "dont", "didnt",
        "wont", "without", "unlike", "contrary", "false", "incorrect"
    ]

    /// Words that open a question and carry no subject of their own.
    static let questionWords: Set<String> = [
        "what", "when", "where", "who", "whom", "whose", "why", "how", "which"
    ]

    /// Prepositions that introduce a qualifier the answer has to respect.
    ///
    /// `between` and `in` are left out on purpose: "the difference between A and B"
    /// would lose its subject to a qualifier that is not one, and a wrong split costs
    /// more than a missing aspect.
    static let constraintMarkers: Set<String> = [
        "during", "under", "before", "after", "within"
    ]

    /// Words that end one clause and start another, so a negation in the second does
    /// not reach back into the first.
    static let clauseConjunctions: Set<String> = [
        "and", "but", "however", "though", "while", "whereas"
    ]

    static let timeUnits: Set<String> = [
        "millisecond", "milliseconds", "second", "seconds", "minute", "minutes",
        "hour", "hours", "day", "days", "week", "weeks", "month", "months",
        "year", "years", "quarter", "quarters"
    ]

    static let monthNames: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december"
    ]

    static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "twenty", "thirty", "forty", "fifty",
        "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million"
    ]

    static let causalConnectives: Set<String> = [
        "because", "due", "owing", "therefore", "hence", "caused", "causes", "reason"
    ]

    /// The attribute a question demands, when it demands one this kit can check.
    ///
    /// Returns `nil` for `what`, `which`, `who` and `where`, and for bare `how`. The
    /// information need of those questions lives in the subject, and raising an
    /// attribute aspect that no passage can satisfy turns every such question into a
    /// refusal.
    static func attributeProbe(in tokens: [String]) -> (probe: AttributeProbe, surface: String)? {
        for (index, token) in tokens.enumerated() {
            switch token {
            case "when":
                return (.time, "a time")
            case "why":
                return (.cause, "a cause")
            case "how":
                let follower = index + 1 < tokens.count ? tokens[index + 1] : ""
                if follower == "many" || follower == "much" {
                    return (.quantity, "a quantity")
                }
            default:
                continue
            }
        }
        return nil
    }

    /// Whether a clause contains a statement of the shape the probe is looking for.
    static func satisfies(_ probe: AttributeProbe, in tokens: [String]) -> Bool {
        switch probe {
        case .time:
            return tokens.contains(where: isTimeExpression)
        case .quantity:
            return tokens.contains(where: isQuantity)
        case .cause:
            return tokens.contains { causalConnectives.contains($0) }
        }
    }

    /// A four-digit year, a month, or a unit of duration.
    static func isTimeExpression(_ token: String) -> Bool {
        if token.count == 4, token.allSatisfy(\.isNumber) { return true }
        return timeUnits.contains(token) || monthNames.contains(token)
    }

    static func isQuantity(_ token: String) -> Bool {
        if token.allSatisfy(\.isNumber), !token.isEmpty { return true }
        return numberWords.contains(token)
    }

    /// Splits text into lowercase word tokens, keeping intra-word hyphens and
    /// dropping apostrophes so `doesn't` and `doesnt` read as the same cue.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "-" {
                current.append(character)
            } else if character == "'" || character == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Splits a passage into clauses.
    ///
    /// Clauses rather than sentences, because negation scopes over a clause. "The
    /// response cache is scoped to one process and is not shared across hosts" denies
    /// something about sharing, not about the cache — and reading it whole turns a
    /// passage that supports the subject into one that contradicts it.
    ///
    /// Over-splitting is the safe direction. A clause boundary that should not be there
    /// costs some conjunctive matching strength; one that is missing invents a denial,
    /// and an invented denial becomes a refusal the caller cannot account for.
    static func clauses(in text: String) -> [String] {
        text.split(whereSeparator: { ".!?;\n,:".contains($0) })
            .flatMap { splitOnConjunctions(String($0)) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func splitOnConjunctions(_ sentence: String) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        for word in sentence.split(separator: " ") {
            let normalized = word.lowercased().filter(\.isLetter)
            if clauseConjunctions.contains(normalized) {
                if !current.isEmpty {
                    parts.append(current.joined(separator: " "))
                    current = []
                }
            } else {
                current.append(String(word))
            }
        }
        if !current.isEmpty {
            parts.append(current.joined(separator: " "))
        }
        return parts
    }

    /// Whether a token carries an information need.
    static func isContentWord(_ token: String) -> Bool {
        token.count > 1 && !stopWords.contains(token)
    }
}
