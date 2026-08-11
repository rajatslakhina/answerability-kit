import AnswerabilityKit
import Foundation

// A retrieval score says how much the corpus *looks like* the question.
// It is the thing most pipelines gate on, so it is the thing worth measuring against.
struct SimilarityBaseline {
    let admitThreshold: Double

    func bestSimilarity(for question: Question, in evidence: [EvidenceItem]) -> Double {
        let wanted = Set(DemoLexicon.contentTerms(of: question.text))
        guard !wanted.isEmpty else { return 0 }
        var best = 0.0
        for item in evidence {
            let have = Set(DemoLexicon.contentTerms(of: item.text))
            best = max(best, Double(wanted.intersection(have).count) / Double(wanted.count))
        }
        return best
    }

    func admits(_ question: Question, in evidence: [EvidenceItem]) -> Bool {
        bestSimilarity(for: question, in: evidence) >= admitThreshold
    }
}

// The demo needs the same tokenisation the kit uses, and the kit keeps its own
// internal. Re-stating it here keeps the baseline honest: it is not handicapped by
// reading the corpus differently from the thing it is being compared against.
enum DemoLexicon {
    static let stop: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "do", "does", "did",
        "have", "has", "had", "will", "would", "can", "could", "of", "to", "and",
        "or", "if", "that", "this", "it", "its", "we", "you", "they", "them",
        "at", "by", "on", "as", "so", "any", "all", "our", "their", "about",
        "with", "from", "into", "for", "in", "not", "what", "when", "why",
        "how", "who", "where", "which"
    ]

    static func contentTerms(of text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
            .filter { $0.count > 1 && !stop.contains($0) }
    }
}

struct Scenario {
    let title: String
    let note: String
    let question: String
    let evidence: [EvidenceItem]
    let policy: AnswerabilityPolicy
}

// MARK: - Corpus

let aggregatorCorpus = [
    EvidenceItem(
        id: "doc-agg-overview",
        text: """
        The streaming aggregator merges partial deltas from every provider into one ordered stream. \
        The streaming aggregator buffers out-of-order chunks until the sequence is contiguous. \
        Operators tune the streaming aggregator through the buffer depth setting.
        """
    ),
    EvidenceItem(
        id: "doc-agg-tuning",
        text: """
        A deep buffer in the streaming aggregator trades latency for completeness. \
        The streaming aggregator drops frames once the buffer is saturated.
        """
    )
]

let cacheCorpus = [
    EvidenceItem(
        id: "kb-cache-ttl",
        text: """
        The response cache holds entries for a time-to-live of nine hundred seconds. \
        Entries in the response cache are evicted when that time expires.
        """
    ),
    EvidenceItem(
        id: "kb-cache-scope",
        text: "The response cache is scoped to one process and is not shared across hosts."
    )
]

let retryCorpus = [
    EvidenceItem(
        id: "kb-retry-current",
        text: "The provider gateway retries a failed request up to five times before giving up."
    ),
    EvidenceItem(
        id: "kb-retry-legacy",
        text: "The provider gateway does not retry a failed request; the caller owns that decision."
    )
]

let scenarios = [
    Scenario(
        title: "1. Answerable",
        note: "Both gates agree. This is the case that has to keep working.",
        question: "What is the time-to-live of the response cache?",
        evidence: cacheCorpus,
        policy: .lenient
    ),
    Scenario(
        title: "2. The corpus is about the subject and never states the fact",
        note: "The failure a similarity score is structurally unable to see.",
        question: "When did the streaming aggregator start dropping frames?",
        evidence: aggregatorCorpus,
        policy: .lenient
    ),
    Scenario(
        title: "3. Evidence disagrees with itself",
        note: "Plenty of coverage. Retrieving more makes this worse, not better.",
        question: "How many times does the provider gateway retry?",
        evidence: retryCorpus,
        policy: .lenient
    ),
    Scenario(
        title: "4. The question could not be read",
        note: "Not the same as unanswerable, and the remedy is not the same either.",
        question: "What about it?",
        evidence: cacheCorpus,
        policy: .lenient
    ),
    Scenario(
        title: "5. Retrieval returned nothing",
        note: "There is no evidence to find insufficient.",
        question: "What is the time-to-live of the response cache?",
        evidence: [],
        policy: .lenient
    ),
    Scenario(
        title: "6. Two of three aspects covered, lenient",
        note: "The qualifier is unmet; a majority is still enough to send.",
        question: "When was the response cache limit raised during the July migration?",
        evidence: cacheCorpus,
        policy: .lenient
    ),
    Scenario(
        title: "7. The same question, strict",
        note: "requiredCoverage 1.0 - raising it blocks MORE.",
        question: "When was the response cache limit raised during the July migration?",
        evidence: cacheCorpus,
        policy: .strict
    ),
    Scenario(
        title: "8. Scenario 2 again, with minimumAspects raised to 3",
        note: "Raising the other knob blocks LESS: a refusal becomes a declined ruling.",
        question: "When did the streaming aggregator start dropping frames?",
        evidence: aggregatorCorpus,
        policy: AnswerabilityPolicy(
            requiredCoverage: 0.6,
            supportThreshold: 0.4,
            minimumAspects: 3,
            conflictMargin: 0.2
        )
    )
]

// MARK: - Reporting

func describe(_ verdict: AnswerabilityVerdict) -> String {
    switch verdict {
    case .answerable:
        return "ANSWERABLE"
    case .insufficient(let missing):
        return "BLOCKED insufficient - missing: \(missing.joined(separator: " | "))"
    case .contested(let aspects):
        return "BLOCKED contested - disputed: \(aspects.joined(separator: " | "))"
    case .undetermined(.tooFewAspects(let found, let required)):
        return "UNDETERMINED - \(found) aspect(s) read, \(required) required to rule"
    case .undetermined(.noEvidenceOffered):
        return "UNDETERMINED - no evidence offered"
    }
}

func percent(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.0f%%", value * 100)
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// One aspect's line: what it wanted, how strongly the corpus answered, and from where.
/// A denying source is prefixed `!`, so a contested aspect reads as a conflict at a glance.
func row(for assessment: AspectAssessment) -> String {
    let sources = assessment.affirmingSources + assessment.denyingSources.map { "!\($0)" }
    let listed = sources.isEmpty ? "-" : sources.joined(separator: ", ")
    let strengths = String(format: "affirm %.2f  deny %.2f", assessment.affirming, assessment.denying)
    return pad(assessment.aspect.kind.rawValue, 11) + pad(assessment.aspect.surface, 34) + strengths + "  " + listed
}

// MARK: - Run

let baseline = SimilarityBaseline(admitThreshold: 0.5)
let gate = AnswerabilityGate(engine: AnswerabilityEngine(policy: .lenient))

print("AnswerabilityKit - deciding whether a question is worth paying to answer")
print(String(repeating: "=", count: 78))

var divergences = 0
var baselineAdmits = 0

for scenario in scenarios {
    let question = Question(scenario.question)
    // The running tally below describes one configuration. Scenarios that vary the
    // policy are shown for contrast and left out of it, because a total summed across
    // three different policies is a number about nothing in particular.
    let tallied = scenario.policy == AnswerabilityPolicy.lenient
    let report: AnswerabilityReport
    if tallied {
        report = await gate.admit(question, evidence: scenario.evidence)
    } else {
        report = AnswerabilityEngine(policy: scenario.policy).assess(question, against: scenario.evidence)
    }

    let similarity = baseline.bestSimilarity(for: question, in: scenario.evidence)
    let baselineAdmitted = baseline.admits(question, in: scenario.evidence)
    let kitAdmitted = report.approvedQuestion != nil
    if tallied {
        if baselineAdmitted { baselineAdmits += 1 }
        if baselineAdmitted != kitAdmitted { divergences += 1 }
    }

    print("")
    print(scenario.title)
    print("  \(scenario.note)")
    print("  Q: \(scenario.question)")
    print("  evidence: \(scenario.evidence.count) passage(s)")
    print("  baseline (similarity \(percent(similarity)) >= 50%): \(baselineAdmitted ? "SEND" : "refuse")")
    print("  AnswerabilityKit: \(describe(report.verdict))")
    print("  coverage: \(percent(report.coverageRate()))")
    for assessment in report.assessments {
        print("    " + row(for: assessment))
    }
    if let reason = report.blockingReason {
        print("  refusal reaching the caller: \(reason)")
    }
    if let unjudged = report.unjudgedQuestion {
        print("  passed through unjudged, caller decides: \(unjudged)")
    }
}

// MARK: - What it cost, and what it saved

let stats = await gate.statistics()
let pricePerCall = 0.0021
let tallied = scenarios.filter { $0.policy == AnswerabilityPolicy.lenient }.count

print("")
print(String(repeating: "=", count: 78))
print("tally covers the \(tallied) lenient scenarios; 7 and 8 vary the policy and are excluded")
print("gate ruled on \(stats.ruled) of \(tallied) questions, declined to rule on \(stats.undetermined)")
print("  admitted              \(stats.admitted)")
print("  blocked insufficient  \(stats.blockedInsufficient)")
print("  blocked contested     \(stats.blockedContested)")
print("  abstention rate       \(percent(stats.abstentionRate()))")
print("")
print("baseline would have sent \(baselineAdmits), the gate sent \(stats.admitted)")
print("send decisions that differ from the baseline: \(divergences)")
print(String(format: "provider spend avoided at $%.4f/call: $%.4f", pricePerCall, Double(stats.blocked) * pricePerCall))
