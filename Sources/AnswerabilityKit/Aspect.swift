import Foundation

/// What a question is asking for, split into the pieces an answer has to cover.
///
/// "When did the streaming aggregator start dropping frames?" needs three things
/// to be answerable: the subject (`streaming aggregator`), the property being
/// asked about (`dropping frames`), and a time. Evidence that covers two of the
/// three produces an answer that is confidently wrong about the third.
public struct InformationAspect: Sendable, Hashable {
    /// The normalised content terms this aspect needs to find in evidence.
    public let terms: [String]
    /// Terms that must appear in the *same sentence* for a match to count.
    ///
    /// Empty for most aspects. An attribute aspect carries the subject's terms here,
    /// because a passage that happens to contain the word `version` somewhere has not
    /// told you which version *this subject* is on. Without the anchor, any long
    /// document satisfies `when` by accident.
    public let anchorTerms: [String]
    /// A human-readable label for reports and refusal messages.
    public let surface: String
    public let kind: AspectKind

    /// The shape of statement that satisfies this aspect, when the aspect is an attribute.
    ///
    /// `nil` for subjects and constraints, which are satisfied by their own terms.
    public let probe: AttributeProbe?

    public init(
        terms: [String],
        anchorTerms: [String] = [],
        surface: String,
        kind: AspectKind,
        probe: AttributeProbe? = nil
    ) {
        self.terms = terms
        self.anchorTerms = anchorTerms
        self.surface = surface
        self.kind = kind
        self.probe = probe
    }
}

/// What an attribute aspect looks for in a passage.
///
/// A probe tests the *shape* of a statement rather than its vocabulary, which is the
/// difference between working and not. Asking whether a passage contains the word
/// `time` finds "buffers chunks until the sequence is contiguous" and calls it a
/// timestamp. Asking whether it contains a time expression does not.
///
/// There are deliberately only three. `who`, `where` and bare `how` have no lexical
/// shape this kit can test honestly, so no attribute aspect is raised for them and the
/// question is judged on its subject alone. That is under-detection, and it is the
/// right direction to fail: an aspect that can never be satisfied refuses every
/// question carrying it, which is how the first draft of this kit blocked "what is the
/// time-to-live of the response cache?" against a corpus that states the answer.
public enum AttributeProbe: String, Sendable, Hashable, CaseIterable {
    /// A year, a month name, or a unit of duration.
    case time
    /// A numeral or a number word.
    case quantity
    /// A causal connective.
    case cause
}

/// Why an aspect is required, which is also what a caller should do when it is missing.
public enum AspectKind: String, Sendable, Hashable, CaseIterable {
    /// The thing the question is about. Missing means the corpus is about something else.
    case subject
    /// The property being asked for, tested by an ``AttributeProbe``. Missing means the
    /// corpus discusses the subject at length and never states the fact requested — the
    /// failure a similarity score is least able to see, because such a corpus scores highly.
    case attribute
    /// A qualifier the answer must respect: a date, a version, a condition.
    case constraint
}

/// Which way a single passage points on a single aspect.
public enum Polarity: String, Sendable, Hashable {
    case affirms
    case denies
}

/// How strongly one passage speaks to one aspect, and in which direction.
public struct AspectSupport: Sendable, Hashable {
    /// Fraction of the aspect's terms found in the best-matching sentence, `0...1`.
    public let strength: Double
    public let polarity: Polarity

    public init(strength: Double, polarity: Polarity) {
        self.strength = strength
        self.polarity = polarity
    }

    /// A passage that says nothing about this aspect.
    public static let none = AspectSupport(strength: 0, polarity: .affirms)
}
