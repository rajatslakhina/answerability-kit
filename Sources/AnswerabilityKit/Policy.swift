import Foundation

/// The four numbers that decide when the gate says no, and when it declines to say anything.
///
/// Two of these pull against each other on purpose.
///
/// `requiredCoverage` guards against **answering with gaps**: raise it and more
/// questions are blocked, fewer provider calls are wasted, and more answerable
/// questions are refused by mistake.
///
/// `minimumAspects` guards against **blocking a question the gate never understood**:
/// raise it and more questions come back ``AnswerabilityVerdict/undetermined(_:)``
/// instead of blocked, which means the gate blocks *less*.
///
/// A gate with only the first confidently refuses questions it could not read.
/// A gate with only the second refuses nothing at all. Both knobs are needed, and
/// where they land is a product decision rather than a fact about the corpus.
public struct AnswerabilityPolicy: Sendable, Hashable {
    /// Fraction of the question's aspects that must be covered before the gate admits it, `0...1`.
    public let requiredCoverage: Double
    /// The per-aspect bar: fraction of an aspect's terms a passage must carry to count as speaking to it.
    public let supportThreshold: Double
    /// Below this many extracted aspects the gate declines to judge rather than blocking.
    public let minimumAspects: Int
    /// How close affirming and denying strengths must be before disagreement counts as a genuine conflict.
    ///
    /// Raising it treats more lopsided disagreements as conflicts, so the gate reports
    /// ``AnswerabilityVerdict/contested(aspects:)`` more often.
    public let conflictMargin: Double

    public init(
        requiredCoverage: Double,
        supportThreshold: Double,
        minimumAspects: Int,
        conflictMargin: Double
    ) {
        self.requiredCoverage = requiredCoverage
        self.supportThreshold = supportThreshold
        self.minimumAspects = minimumAspects
        self.conflictMargin = conflictMargin
    }

    /// Every aspect must be covered. Appropriate when a wrong answer costs more than a refusal.
    public static let strict = AnswerabilityPolicy(
        requiredCoverage: 1.0,
        supportThreshold: 0.5,
        minimumAspects: 1,
        conflictMargin: 0.35
    )

    /// A majority of aspects must be covered. Appropriate for conversational use, where
    /// the cost of refusing an ordinary question is high and the user can follow up.
    public static let lenient = AnswerabilityPolicy(
        requiredCoverage: 0.6,
        supportThreshold: 0.4,
        minimumAspects: 1,
        conflictMargin: 0.2
    )
}
