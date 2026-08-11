import Foundation

/// The decision procedure: aspects in, verdict out, no state and no I/O.
///
/// Synchronous and a value type on purpose. The judgement is a pure function of the
/// question, the evidence and the policy, so it is testable without a runtime and
/// callable from anywhere. Only the counting is stateful, and that lives in
/// ``AnswerabilityGate``.
public struct AnswerabilityEngine: Sendable {
    public let policy: AnswerabilityPolicy
    private let extractor: any AspectExtracting
    private let matcher: any EvidenceMatching

    public init(
        policy: AnswerabilityPolicy = .lenient,
        extractor: any AspectExtracting = LexicalAspectExtractor(),
        matcher: any EvidenceMatching = LexicalEvidenceMatcher()
    ) {
        self.policy = policy
        self.extractor = extractor
        self.matcher = matcher
    }

    /// Decides whether this question is worth sending, given this evidence.
    ///
    /// The two `undetermined` exits come first and deliberately do not block. A gate
    /// that cannot read the question, or was handed nothing to read, has not found the
    /// question unanswerable — it has failed to form an opinion, and dressing that up
    /// as a refusal would be the gate asserting something it did not establish.
    public func assess(_ question: Question, against evidence: [EvidenceItem]) -> AnswerabilityReport {
        let aspects = extractor.aspects(in: question)
        guard aspects.count >= policy.minimumAspects else {
            return AnswerabilityReport(
                question: question,
                assessments: [],
                verdict: .undetermined(.tooFewAspects(found: aspects.count, required: policy.minimumAspects)),
                evidenceCount: evidence.count
            )
        }
        guard !evidence.isEmpty else {
            return AnswerabilityReport(
                question: question,
                assessments: [],
                verdict: .undetermined(.noEvidenceOffered),
                evidenceCount: 0
            )
        }
        let assessments = aspects.map { assess(aspect: $0, against: evidence) }
        return AnswerabilityReport(
            question: question,
            assessments: assessments,
            verdict: rule(on: assessments),
            evidenceCount: evidence.count
        )
    }

    /// Conflict is reported ahead of a gap.
    ///
    /// Both can hold at once, and `assessments` carries the whole picture either way.
    /// The verdict names the remedy, and the remedies differ: a gap is fixed by
    /// retrieving more, while a conflict is made worse by it. Reporting the gap first
    /// would send a caller to do the one thing that cannot help.
    private func rule(on assessments: [AspectAssessment]) -> AnswerabilityVerdict {
        let contested = assessments.filter(\.isContested).map(\.aspect.surface)
        guard contested.isEmpty else { return .contested(aspects: contested) }

        let missing = assessments.filter { !$0.isCovered }.map(\.aspect.surface)
        let coverage = Double(assessments.count - missing.count) / Double(assessments.count)
        guard coverage >= policy.requiredCoverage - Self.tolerance else {
            return .insufficient(missing: missing)
        }
        return .answerable
    }

    private func assess(aspect: InformationAspect, against evidence: [EvidenceItem]) -> AspectAssessment {
        var affirming = 0.0
        var denying = 0.0
        var affirmingSources: [String] = []
        var denyingSources: [String] = []

        for item in evidence {
            let support = matcher.support(for: aspect, in: item)
            guard support.strength >= policy.supportThreshold else { continue }
            switch support.polarity {
            case .affirms:
                affirming = max(affirming, support.strength)
                affirmingSources.append(item.id)
            case .denies:
                denying = max(denying, support.strength)
                denyingSources.append(item.id)
            }
        }

        return AspectAssessment(
            aspect: aspect,
            affirming: affirming,
            denying: denying,
            affirmingSources: affirmingSources,
            denyingSources: denyingSources,
            // A denial covers the aspect. "Is the cache shared?" is answerable by a
            // passage saying it is not — evidence against a proposition is still
            // evidence about it, and only silence leaves the question open.
            isCovered: !affirmingSources.isEmpty || !denyingSources.isEmpty,
            isContested: !affirmingSources.isEmpty
                && !denyingSources.isEmpty
                && abs(affirming - denying) <= policy.conflictMargin
        )
    }

    /// Guards the `requiredCoverage: 1.0` case against binary floating-point error.
    private static let tolerance = 1e-9
}
