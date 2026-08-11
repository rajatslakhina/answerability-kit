import Foundation

/// What the evidence set had to say about one aspect of the question.
public struct AspectAssessment: Sendable, Hashable {
    public let aspect: InformationAspect
    /// Strongest affirming support found across the whole evidence set.
    public let affirming: Double
    /// Strongest denying support found across the whole evidence set.
    public let denying: Double
    /// Identifiers of the passages that affirmed this aspect at or above the threshold.
    public let affirmingSources: [String]
    /// Identifiers of the passages that denied it at or above the threshold.
    public let denyingSources: [String]
    /// Whether some passage spoke to this aspect strongly enough to count.
    public let isCovered: Bool
    /// Whether affirming and denying passages disagreed closely enough to count as a conflict.
    ///
    /// Contested is not the same as uncovered. A contested aspect has *plenty* of
    /// evidence — which is exactly why a coverage number alone cannot see it.
    public let isContested: Bool

    public init(
        aspect: InformationAspect,
        affirming: Double,
        denying: Double,
        affirmingSources: [String],
        denyingSources: [String],
        isCovered: Bool,
        isContested: Bool
    ) {
        self.aspect = aspect
        self.affirming = affirming
        self.denying = denying
        self.affirmingSources = affirmingSources
        self.denyingSources = denyingSources
        self.isCovered = isCovered
        self.isContested = isContested
    }
}

/// Why the gate declined to judge a question rather than deciding it.
public enum UndeterminedReason: Sendable, Hashable {
    /// The question yielded fewer analysable aspects than the policy requires.
    /// Blocking here would mean refusing a question on the strength of not having read it.
    case tooFewAspects(found: Int, required: Int)
    /// No evidence was offered at all. There is nothing to judge sufficiency *of*,
    /// and reporting "insufficient evidence" would imply evidence was examined.
    case noEvidenceOffered
}

/// The gate's four possible answers. A caller has to handle all four, which is the point.
public enum AnswerabilityVerdict: Sendable, Hashable {
    /// Enough of the question is covered by evidence that is not in conflict with itself.
    case answerable
    /// Named aspects have no passage speaking to them. The remedy is retrieval, or abstention.
    case insufficient(missing: [String])
    /// Named aspects are covered by passages that contradict each other.
    /// The remedy is not more retrieval — it is picking a source, or telling the user why not.
    case contested(aspects: [String])
    /// The gate refuses to rule. This is not a soft block; it is the absence of a ruling.
    case undetermined(UndeterminedReason)
}

/// The gate's finding, shaped so a caller cannot spend money by forgetting to read it.
public struct AnswerabilityReport: Sendable, Hashable {
    public let question: Question
    public let assessments: [AspectAssessment]
    public let verdict: AnswerabilityVerdict
    /// How many passages were examined. Reported so a coverage figure can be read
    /// against the size of the set it was computed over.
    public let evidenceCount: Int

    public init(
        question: Question,
        assessments: [AspectAssessment],
        verdict: AnswerabilityVerdict,
        evidenceCount: Int
    ) {
        self.question = question
        self.assessments = assessments
        self.verdict = verdict
        self.evidenceCount = evidenceCount
    }

    /// Fraction of aspects covered, or `nil` when no aspects were extracted.
    ///
    /// `nil` rather than `0`: a question the gate could not decompose has no coverage
    /// rate, and printing 0% for work that was never done is a number the caller
    /// cannot check. Same reason `resolutionRate` and `attributionRate` are optional
    /// elsewhere in this ecosystem.
    public func coverageRate() -> Double? {
        guard !assessments.isEmpty else { return nil }
        let covered = assessments.filter(\.isCovered).count
        return Double(covered) / Double(assessments.count)
    }

    /// The question, if and only if the gate approved sending it.
    ///
    /// `nil` for every other verdict, including ``AnswerabilityVerdict/undetermined(_:)``.
    /// A caller that reads only this property fails closed: an unjudged question is not
    /// forwarded by accident, because there is no text here to forward.
    public var approvedQuestion: String? {
        guard verdict == .answerable else { return nil }
        return question.text
    }

    /// The question, if and only if the gate declined to rule on it.
    ///
    /// Separate from ``approvedQuestion`` so that sending an unjudged question is a
    /// decision a caller makes in the open, named in its own code, rather than a
    /// default it inherits.
    public var unjudgedQuestion: String? {
        guard case .undetermined = verdict else { return nil }
        return question.text
    }

    /// Why the gate blocked, or `nil` when it did not block.
    public var blockingReason: String? {
        switch verdict {
        case .answerable, .undetermined:
            return nil
        case .insufficient(let missing):
            return "no evidence covers: " + missing.joined(separator: ", ")
        case .contested(let aspects):
            return "evidence disagrees about: " + aspects.joined(separator: ", ")
        }
    }
}
