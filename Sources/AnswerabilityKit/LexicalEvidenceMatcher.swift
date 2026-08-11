import Foundation

/// Scores a passage against an aspect, one sentence at a time.
///
/// Sentence-level rather than document-level, because polarity does not survive
/// aggregation: a page stating a limit in one paragraph and its removal in another
/// has not half-affirmed the limit. Reading the whole passage at once would average
/// a contradiction into mild agreement, which is the one outcome that must not happen
/// — the disagreement is the finding.
public struct LexicalEvidenceMatcher: EvidenceMatching {
    public init() {}

    public func support(for aspect: InformationAspect, in item: EvidenceItem) -> AspectSupport {
        var best = AspectSupport.none
        for clause in Lexicon.clauses(in: item.text) {
            guard let candidate = support(for: aspect, inClause: clause) else { continue }
            if candidate.strength > best.strength {
                best = candidate
            }
        }
        return best
    }

    private func support(for aspect: InformationAspect, inClause clause: String) -> AspectSupport? {
        let tokens = Lexicon.tokenize(clause)
        let present = Set(tokens)
        guard aspect.anchorTerms.isEmpty || aspect.anchorTerms.contains(where: { present.contains($0) }) else {
            return nil
        }
        guard let strength = strength(of: aspect, in: tokens, present: present) else { return nil }
        let negated = present.contains { Lexicon.negationCues.contains($0) }
        return AspectSupport(strength: strength, polarity: negated ? .denies : .affirms)
    }

    /// An attribute is satisfied whole or not at all — a clause either states a time or
    /// it does not. A subject or constraint is satisfied in proportion, because losing
    /// half the words of `streaming aggregator buffer` leaves a different subject.
    private func strength(of aspect: InformationAspect, in tokens: [String], present: Set<String>) -> Double? {
        if let probe = aspect.probe {
            return Lexicon.satisfies(probe, in: tokens) ? 1.0 : nil
        }
        let hits = aspect.terms.filter { present.contains($0) }.count
        guard hits > 0 else { return nil }
        return Double(hits) / Double(aspect.terms.count)
    }
}
