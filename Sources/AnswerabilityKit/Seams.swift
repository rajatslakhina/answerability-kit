import Foundation

/// Turns a question into the set of things an answer has to cover.
///
/// The default implementation is lexical and dependency-free. This protocol exists so
/// it can be replaced by a tagger, a parser or a model without touching the policy or
/// the refusals — the part of the kit worth trusting is the decision procedure, not
/// the English heuristics feeding it.
public protocol AspectExtracting: Sendable {
    func aspects(in question: Question) -> [InformationAspect]
}

/// Decides how strongly one passage speaks to one aspect, and in which direction.
///
/// Replaceable for the same reason: an embedding model would score the same aspects
/// against the same passages and feed the same policy. Swapping it changes how well
/// the gate reads evidence, never what it does with what it read.
public protocol EvidenceMatching: Sendable {
    func support(for aspect: InformationAspect, in item: EvidenceItem) -> AspectSupport
}
