import Foundation

/// Splits a question into a subject, the attribute being asked for, and any qualifier.
///
/// Every rule here is lexical and listed in ``Lexicon``. It is the weakest part of the
/// kit by design: it sits behind ``AspectExtracting`` so it can be replaced, and the
/// gate's behaviour is defined by ``AnswerabilityPolicy`` rather than by these rules.
public struct LexicalAspectExtractor: AspectExtracting {
    public init() {}

    public func aspects(in question: Question) -> [InformationAspect] {
        let tokens = Lexicon.tokenize(question.text)
        let (constraintTerms, body) = splitConstraint(from: tokens)
        let subjectTerms = body.filter { Lexicon.isContentWord($0) && !Lexicon.questionWords.contains($0) }

        var result: [InformationAspect] = []
        if !subjectTerms.isEmpty {
            result.append(
                InformationAspect(
                    terms: subjectTerms,
                    surface: subjectTerms.joined(separator: " "),
                    kind: .subject
                )
            )
        }
        if let attribute = attributeAspect(from: tokens, anchoredTo: subjectTerms) {
            result.append(attribute)
        }
        if !constraintTerms.isEmpty {
            result.append(
                InformationAspect(
                    terms: constraintTerms,
                    surface: constraintTerms.joined(separator: " "),
                    kind: .constraint
                )
            )
        }
        return result
    }

    /// The attribute the question demands, anchored to the subject so that a stray
    /// time expression in an unrelated clause cannot satisfy `when`.
    ///
    /// A question with no subject gets no attribute aspect either. An unanchored probe
    /// is satisfied by any passage long enough to contain a number, which would make
    /// the gate admit questions on the strength of the corpus being verbose.
    private func attributeAspect(from tokens: [String], anchoredTo subject: [String]) -> InformationAspect? {
        guard !subject.isEmpty, let found = Lexicon.attributeProbe(in: tokens) else { return nil }
        return InformationAspect(
            terms: [],
            anchorTerms: subject,
            surface: found.surface,
            kind: .attribute,
            probe: found.probe
        )
    }

    /// Separates a trailing qualifier from the rest of the question.
    ///
    /// Only unambiguous qualifier prepositions are recognised. `between` and `in` are
    /// left out on purpose: "the difference between A and B" would lose its subject to
    /// a qualifier that is not one, and a wrong split is worse than a missing aspect.
    private func splitConstraint(from tokens: [String]) -> (constraint: [String], body: [String]) {
        guard let index = tokens.firstIndex(where: { Lexicon.constraintMarkers.contains($0) }) else {
            return ([], tokens)
        }
        let qualifier = tokens[(index + 1)...].filter(Lexicon.isContentWord)
        return (Array(qualifier), Array(tokens[..<index]))
    }
}
