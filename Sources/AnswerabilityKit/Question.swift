import Foundation

/// A question a caller is about to spend money answering.
///
/// The gate examines the question and the evidence a retriever produced for it,
/// and decides whether the call is worth making at all. Everything upstream of a
/// provider call is free; everything downstream of it is not.
public struct Question: Sendable, Hashable {
    /// The question as the user asked it, unmodified.
    public let text: String

    public init(_ text: String) {
        self.text = text
    }
}

/// One retrieved passage offered as evidence for a question.
///
/// The identifier is the caller's — a document id, a chunk id, a URL. The kit
/// never invents one, because a report that names its evidence with an index
/// into an array the caller no longer holds is a report the caller cannot check.
public struct EvidenceItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}
