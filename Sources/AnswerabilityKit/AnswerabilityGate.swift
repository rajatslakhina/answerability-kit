import Foundation

/// What the gate has done so far, in numbers a caller can put in front of someone.
public struct GateStatistics: Sendable, Hashable {
    public private(set) var admitted = 0
    public private(set) var blockedInsufficient = 0
    public private(set) var blockedContested = 0
    public private(set) var undetermined = 0

    public init() {}

    /// Questions the gate actually ruled on. Excludes the ones it declined to judge,
    /// because those are not rulings and counting them as such would flatter the rate.
    public var ruled: Int { admitted + blockedInsufficient + blockedContested }

    /// Provider calls this gate prevented.
    public var blocked: Int { blockedInsufficient + blockedContested }

    /// Share of ruled questions that were blocked, or `nil` when nothing was ruled on.
    ///
    /// `nil` rather than `0`: a gate that has judged nothing does not have a 0%
    /// abstention rate, it has no abstention rate. Same reason
    /// ``AnswerabilityReport/coverageRate()`` is optional.
    public func abstentionRate() -> Double? {
        guard ruled > 0 else { return nil }
        return Double(blocked) / Double(ruled)
    }

    fileprivate mutating func record(_ verdict: AnswerabilityVerdict) {
        switch verdict {
        case .answerable: admitted += 1
        case .insufficient: blockedInsufficient += 1
        case .contested: blockedContested += 1
        case .undetermined: undetermined += 1
        }
    }
}

/// Serialises the gate's running totals across concurrent callers.
///
/// The actor owns the counters and nothing else. The judgement itself is in
/// ``AnswerabilityEngine``, which is a synchronous value type — so a caller wanting a
/// verdict without a hop has one, and a caller wanting statistics across a session
/// gets them without a lock of its own.
public actor AnswerabilityGate {
    private let engine: AnswerabilityEngine
    private var stats = GateStatistics()

    public init(engine: AnswerabilityEngine = AnswerabilityEngine()) {
        self.engine = engine
    }

    /// Judges one question and counts the result.
    @discardableResult
    public func admit(_ question: Question, evidence: [EvidenceItem]) -> AnswerabilityReport {
        let report = engine.assess(question, against: evidence)
        stats.record(report.verdict)
        return report
    }

    public func statistics() -> GateStatistics { stats }
}
