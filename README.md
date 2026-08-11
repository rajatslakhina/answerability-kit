# AnswerabilityKit

Decide whether a question is worth paying to answer — before the provider call, not after it.

Every other verification package in this ecosystem runs downstream of a model that has
already been paid: grounding, citation binding, claim consistency, decontextualization.
They tell you the answer was wrong. `AnswerabilityKit` runs upstream and tells you the
answer was never going to be right, because the evidence to produce it was not there.

```
retrieve ──▶ AnswerabilityKit ──▶ [$$ provider call] ──▶ grounding ──▶ citations ──▶ …
                    │
                    └── blocked: no call is made, and the user is told why
```

## The failure it exists for

A similarity score says how much the retrieved corpus *looks like* the question. That is
not the same as covering it, and the gap is not a rounding error:

> **Q: When did the streaming aggregator start dropping frames?**
> Corpus: three passages about the streaming aggregator, its buffer, and frame drops.
> Similarity: **60%** — comfortably over any sane threshold.
> Times mentioned anywhere in the corpus: **none.**

The corpus is *about* the subject, at length, which is exactly why it scores well. A
retrieval gate sends this question. The model then answers it, because models answer
questions. Research on reasoning models calls this the detection-to-abstention gap —
models often identify the missing information mid-reasoning and produce a definitive
answer regardless ([arXiv 2605.28070](https://arxiv.org/abs/2605.28070)). `AnswerabilityKit`
treats sufficiency as a set-level property of the evidence, in the spirit of SURE-RAG
([arXiv 2605.03534](https://arxiv.org/abs/2605.03534)), and refuses before the money moves.

## Four verdicts, and the fourth is the interesting one

```swift
public enum AnswerabilityVerdict: Sendable, Hashable {
    case answerable
    case insufficient(missing: [String])   // no passage speaks to these aspects
    case contested(aspects: [String])      // passages speak, and contradict each other
    case undetermined(UndeterminedReason)  // the gate declines to rule at all
}
```

`insufficient` and `contested` are two different failures with two different remedies.
A gap is fixed by retrieving more. **A conflict is made worse by retrieving more** — the
remedy is choosing a source, or telling the user the sources disagree. A single coverage
score cannot tell them apart, because a contested aspect has *plenty* of evidence.

`undetermined` is the refusal most gates skip. A gate that always returns a ruling will
confidently block questions it never parsed, and confidently pass questions it was handed
no evidence for. Declining to rule is not a soft block — it is the absence of a ruling,
and the caller has to decide what to do with it.

### The safety property is in a signature, not a convention

```swift
report.approvedQuestion   // String? — non-nil only for .answerable
report.unjudgedQuestion   // String? — non-nil only for .undetermined
report.blockingReason     // String? — non-nil only when blocking
report.coverageRate()     // Double? — nil when no aspects were extracted
```

A caller that reads only `approvedQuestion` **fails closed**: there is no text to forward
for any verdict except approval, so an unjudged question cannot reach the provider by
accident. Sending one anyway is possible, but it requires naming `unjudgedQuestion` in
your own code — a decision made in the open rather than inherited as a default.

`coverageRate()` is `nil` rather than `0` for a question the gate could not decompose.
Reporting 0% coverage for work that was never done is a number the caller cannot check.

## The two knobs pull against each other

```swift
AnswerabilityPolicy(
    requiredCoverage: 0.6,   // ↑ blocks MORE  — guards against answering with gaps
    supportThreshold: 0.4,   //                  per-aspect bar for "speaks to this"
    minimumAspects: 1,       // ↑ blocks LESS  — guards against ruling on an unread question
    conflictMargin: 0.2      //                  how close strengths must be to count as conflict
)
```

A gate with only `requiredCoverage` confidently refuses questions it could not read.
A gate with only `minimumAspects` refuses nothing at all. Where they land is a product
decision, not a fact about your corpus. `.strict` and `.lenient` are supplied.

## Install

```swift
.package(url: "https://github.com/rajatslakhina/answerability-kit.git", from: "1.0.0")
```

## Usage

```swift
import AnswerabilityKit

let gate = AnswerabilityGate(engine: AnswerabilityEngine(policy: .lenient))

let report = await gate.admit(
    Question("When did the streaming aggregator start dropping frames?"),
    evidence: retrieved.map { EvidenceItem(id: $0.documentID, text: $0.text) }
)

switch report.verdict {
case .answerable:
    // report.approvedQuestion is non-nil here, and only here.
    let answer = try await session.send(prompt(for: report.approvedQuestion))

case .insufficient, .contested:
    // A refusal is the system working. Give the user a headline, an explanation
    // and a way forward — report.blockingReason names the aspects that failed.
    show(refusal: report.blockingReason)

case .undetermined(let reason):
    // The gate has no opinion. Yours to make, in the open.
    log("answerability declined to rule: \(reason)")
    let answer = try await session.send(prompt(for: report.unjudgedQuestion))
}
```

Statistics accumulate on the actor across a session:

```swift
let stats = await gate.statistics()
stats.blocked            // provider calls this gate prevented
stats.abstentionRate()   // Double? — nil until something has actually been ruled on
```

## Architecture

| Type | Kind | Role |
|---|---|---|
| `AnswerabilityEngine` | `struct`, synchronous | The decision procedure. Pure, no I/O, no state. |
| `AnswerabilityGate` | `actor` | Owns the running totals and nothing else. |
| `AspectExtracting` | `protocol` | Question → the things an answer must cover. |
| `EvidenceMatching` | `protocol` | (aspect, passage) → strength and polarity. |
| `LexicalAspectExtractor` | `struct` | Default extractor. Dependency-free. |
| `LexicalEvidenceMatcher` | `struct` | Default matcher. Clause-scoped. |

The judgement is a value type so it is callable without a hop and testable without a
runtime; only the counting needs isolation. Both protocols exist so the English
heuristics can be replaced by a tagger, a parser or an embedding model **without touching
the policy or the refusals** — the part worth trusting is the decision procedure, not the
heuristics feeding it.

## Three decisions worth knowing about

**Attribute aspects test a shape, not a vocabulary.** Asking whether a passage contains
the word `time` finds *"buffers chunks until the sequence is contiguous"* and calls it a
timestamp. Asking whether it contains a time expression — a year, a month, a unit of
duration — does not. The first draft used term lists and it inverted the package's own
headline example; the demo caught it before any test did.

**Only three probes exist: `time`, `quantity`, `cause`.** `who`, `where` and bare `how`
have no lexical shape this kit can test honestly, so no attribute aspect is raised for
them and the question is judged on its subject alone. That is deliberate
under-detection. An aspect that can never be satisfied refuses *every* question carrying
it — which is how the first draft blocked "what is the time-to-live of the response
cache?" against a corpus that states the answer in so many words.

**Negation scopes over a clause, not a sentence.** *"The response cache is scoped to one
process and is not shared across hosts"* denies something about sharing, not about the
cache. Read whole, it turns a passage that supports the subject into one that contradicts
it — and an invented contradiction becomes a refusal the caller cannot account for.
Over-splitting is the safe direction: a spurious boundary costs some matching strength,
while a missing one manufactures conflict.

**No `NaturalLanguage`.** A tagger's output moves with the OS version, which would make a
refusal reproducible on one machine and not another.

## Demo

```
swift run AnswerabilityDemo
```

Eight scenarios against a similarity-threshold baseline, including both directions of
divergence — the baseline sending a question with no answer in the corpus, and the
baseline refusing one the gate admits because unmatched qualifier terms dilute its score.

## Quality gates

Measured on this commit, tool-verified:

| Gate | Result |
|---|---|
| `swift build` | 0 warnings, 0 errors |
| `swift test` | 50 tests in 9 suites, 0 failures |
| `llvm-cov report` | **100.00%** regions, functions and lines — all 9 library files |
| `swiftlint --strict` | 0 violations across 12 files (SwiftLint 0.63.2) |

## Part of a larger ecosystem

Built around [ProviderGatewayKit](https://github.com/rajatslakhina/foundation-model-provider-gateway).
See [llm-ecosystem-demo](https://github.com/rajatslakhina/llm-ecosystem-demo) for how the
packages compose, and [ai-chat-app](https://github.com/rajatslakhina/ai-chat-app) for them
running inside a real SwiftUI client.

## Licence

MIT
