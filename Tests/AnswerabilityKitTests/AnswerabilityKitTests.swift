import Testing
@testable import AnswerabilityKit

// MARK: - Fixtures

private let cacheTTL = EvidenceItem(
    id: "kb-ttl",
    text: "The response cache holds entries for a time-to-live of nine hundred seconds."
)
private let cacheScope = EvidenceItem(
    id: "kb-scope",
    text: "The response cache is scoped to one process and is not shared across hosts."
)
private let retryFive = EvidenceItem(
    id: "kb-five",
    text: "The provider gateway retries a failed request up to five times."
)
private let retryNone = EvidenceItem(
    id: "kb-none",
    text: "The provider gateway does not retry a failed request."
)

private func subjectAspect(_ terms: [String]) -> InformationAspect {
    InformationAspect(terms: terms, surface: terms.joined(separator: " "), kind: .subject)
}

private func probeAspect(_ probe: AttributeProbe, anchoredTo anchors: [String]) -> InformationAspect {
    InformationAspect(terms: [], anchorTerms: anchors, surface: "probe", kind: .attribute, probe: probe)
}

// MARK: - Seam stubs

private struct FixedExtractor: AspectExtracting {
    let result: [InformationAspect]
    func aspects(in question: Question) -> [InformationAspect] { result }
}

private struct FixedMatcher: EvidenceMatching {
    let fixed: AspectSupport
    func support(for aspect: InformationAspect, in item: EvidenceItem) -> AspectSupport { fixed }
}

// MARK: - Tokenising

@Suite("Lexicon tokenising")
struct LexiconTokenisingTests {
    @Test func keepsLettersDigitsAndHyphens() {
        #expect(Lexicon.tokenize("time-to-live is 900") == ["time-to-live", "is", "900"])
    }

    @Test func dropsBothApostropheForms() {
        #expect(Lexicon.tokenize("doesn't") == ["doesnt"])
        #expect(Lexicon.tokenize("doesn\u{2019}t") == ["doesnt"])
    }

    @Test func flushesTrailingTokenWithoutSeparator() {
        #expect(Lexicon.tokenize("cache") == ["cache"])
    }

    @Test func endsCleanlyOnASeparator() {
        #expect(Lexicon.tokenize("cache.") == ["cache"])
    }

    @Test func stopWordsAndSingleCharactersCarryNoNeed() {
        #expect(Lexicon.isContentWord("cache"))
        #expect(!Lexicon.isContentWord("the"))
        #expect(!Lexicon.isContentWord("a"))
    }
}

// MARK: - Clauses

@Suite("Lexicon clause splitting")
struct LexiconClauseTests {
    @Test func splitsOnPunctuationAndConjunctions() {
        let clauses = Lexicon.clauses(in: "The cache is warm and the queue is not drained.")
        #expect(clauses == ["The cache is warm", "the queue is not drained"])
    }

    @Test func ignoresALeadingConjunction() {
        #expect(Lexicon.clauses(in: "and but the cache is warm") == ["the cache is warm"])
    }

    @Test func ignoresATrailingConjunction() {
        #expect(Lexicon.clauses(in: "the cache is warm and") == ["the cache is warm"])
    }

    @Test func yieldsNothingForPunctuationOnly() {
        #expect(Lexicon.clauses(in: "...").isEmpty)
    }

    /// The reason clauses exist: a denial in the second half must not reach the first.
    @Test func negationDoesNotCrossAClauseBoundary() {
        let matcher = LexicalEvidenceMatcher()
        let support = matcher.support(for: subjectAspect(["response", "cache"]), in: cacheScope)
        #expect(support.polarity == .affirms)
        #expect(support.strength == 1.0)
    }
}

// MARK: - Probes

@Suite("Attribute probes")
struct ProbeTests {
    @Test func whenAsksForATime() {
        let found = Lexicon.attributeProbe(in: ["when", "did", "it", "ship"])
        #expect(found?.probe == .time)
        #expect(found?.surface == "a time")
    }

    @Test func whyAsksForACause() {
        #expect(Lexicon.attributeProbe(in: ["why", "did", "it", "fail"])?.probe == .cause)
    }

    @Test func howManyAndHowMuchAskForAQuantity() {
        #expect(Lexicon.attributeProbe(in: ["how", "many", "retries"])?.probe == .quantity)
        #expect(Lexicon.attributeProbe(in: ["how", "much", "memory"])?.probe == .quantity)
    }

    @Test func bareHowRaisesNothing() {
        #expect(Lexicon.attributeProbe(in: ["how", "does", "it", "work"]) == nil)
        #expect(Lexicon.attributeProbe(in: ["how"]) == nil)
    }

    @Test func whatAndWhereRaiseNothing() {
        #expect(Lexicon.attributeProbe(in: ["what", "is", "the", "limit"]) == nil)
        #expect(Lexicon.attributeProbe(in: ["where", "is", "the", "host"]) == nil)
    }

    @Test func timeIsAYearAMonthOrADuration() {
        #expect(Lexicon.isTimeExpression("2026"))
        #expect(Lexicon.isTimeExpression("july"))
        #expect(Lexicon.isTimeExpression("days"))
        #expect(!Lexicon.isTimeExpression("abcd"))
        #expect(!Lexicon.isTimeExpression("cache"))
    }

    @Test func quantityIsANumeralOrANumberWord() {
        #expect(Lexicon.isQuantity("42"))
        #expect(Lexicon.isQuantity("five"))
        #expect(!Lexicon.isQuantity("cache"))
        #expect(!Lexicon.isQuantity(""))
    }

    @Test func everyProbeCanBeSatisfiedAndDenied() {
        let satisfying: [AttributeProbe: [String]] = [
            .time: ["shipped", "in", "2026"],
            .quantity: ["five", "retries"],
            .cause: ["failed", "because", "of", "load"]
        ]
        for probe in AttributeProbe.allCases {
            #expect(Lexicon.satisfies(probe, in: satisfying[probe] ?? []))
            #expect(!Lexicon.satisfies(probe, in: ["the", "cache", "is", "warm"]))
        }
    }
}

// MARK: - Extraction

@Suite("Aspect extraction")
struct ExtractionTests {
    private let extractor = LexicalAspectExtractor()

    @Test func aWhatQuestionYieldsOnlyASubject() {
        let aspects = extractor.aspects(in: Question("What is the time-to-live of the response cache?"))
        #expect(aspects.count == 1)
        #expect(aspects[0].kind == .subject)
        #expect(aspects[0].terms == ["time-to-live", "response", "cache"])
        #expect(aspects[0].probe == nil)
    }

    @Test func aWhenQuestionAddsAnAnchoredTimeAspect() {
        let aspects = extractor.aspects(in: Question("When did the streaming aggregator drop frames?"))
        #expect(aspects.count == 2)
        #expect(aspects[1].kind == .attribute)
        #expect(aspects[1].probe == .time)
        #expect(aspects[1].anchorTerms == aspects[0].terms)
    }

    @Test func aQualifierBecomesItsOwnAspect() {
        let aspects = extractor.aspects(in: Question("Why did the cache fail during the July migration?"))
        #expect(aspects.map(\.kind) == [.subject, .attribute, .constraint])
        #expect(aspects[0].terms == ["cache", "fail"])
        #expect(aspects[2].terms == ["july", "migration"])
    }

    @Test func aQualifierMarkerWithNothingAfterItAddsNoAspect() {
        let aspects = extractor.aspects(in: Question("What is the cache during?"))
        #expect(aspects.count == 1)
        #expect(aspects[0].kind == .subject)
    }

    /// An unanchored probe is satisfied by any passage long enough to contain a number.
    @Test func aQuestionWithNoSubjectGetsNoAttributeEither() {
        #expect(extractor.aspects(in: Question("When?")).isEmpty)
    }

    @Test func aQuestionWithNothingInItYieldsNothing() {
        #expect(extractor.aspects(in: Question("What about it?")).isEmpty)
    }
}

// MARK: - Matching

@Suite("Evidence matching")
struct MatchingTests {
    private let matcher = LexicalEvidenceMatcher()

    @Test func scoresASubjectInProportionToTermsFound() {
        let support = matcher.support(for: subjectAspect(["response", "cache", "limit"]), in: cacheTTL)
        #expect(abs(support.strength - 2.0 / 3.0) < 1e-9)
        #expect(support.polarity == .affirms)
    }

    @Test func readsNegationWithinTheClause() {
        let support = matcher.support(for: subjectAspect(["provider", "gateway", "retry"]), in: retryNone)
        #expect(support.polarity == .denies)
    }

    @Test func reportsNothingWhenNoTermIsPresent() {
        #expect(matcher.support(for: subjectAspect(["zebra"]), in: cacheTTL) == AspectSupport.none)
    }

    @Test func keepsTheStrongestClauseRatherThanTheLast() {
        let item = EvidenceItem(id: "two", text: "The response cache is warm. The cache is small.")
        let support = matcher.support(for: subjectAspect(["response", "cache", "warm"]), in: item)
        #expect(abs(support.strength - 1.0) < 1e-9)
    }

    @Test func aSatisfiedProbeScoresWhole() {
        let support = matcher.support(for: probeAspect(.time, anchoredTo: ["response", "cache"]), in: cacheTTL)
        #expect(support.strength == 1.0)
    }

    @Test func anUnsatisfiedProbeScoresNothing() {
        #expect(matcher.support(for: probeAspect(.time, anchoredTo: ["response", "cache"]), in: cacheScope)
            == AspectSupport.none)
    }

    /// A time expression in a clause about something else does not answer this question.
    @Test func theAnchorMustAppearInTheSameClause() {
        #expect(matcher.support(for: probeAspect(.time, anchoredTo: ["zebra"]), in: cacheTTL)
            == AspectSupport.none)
    }
}

// MARK: - Verdicts

@Suite("Engine verdicts")
struct VerdictTests {
    @Test func admitsWhenTheEvidenceCoversTheQuestion() {
        let report = AnswerabilityEngine().assess(
            Question("What is the time-to-live of the response cache?"),
            against: [cacheTTL, cacheScope]
        )
        #expect(report.verdict == .answerable)
        #expect(report.coverageRate() == 1.0)
        #expect(report.evidenceCount == 2)
    }

    /// The whole point: the corpus is about the subject and never states the fact.
    @Test func blocksWhenTheCorpusNeverStatesTheFactAsked() {
        let aggregator = EvidenceItem(
            id: "doc-agg",
            text: "The streaming aggregator buffers chunks until the sequence is contiguous."
        )
        let report = AnswerabilityEngine().assess(
            Question("When did the streaming aggregator start dropping frames?"),
            against: [aggregator]
        )
        #expect(report.verdict == .insufficient(missing: ["a time"]))
        #expect(report.coverageRate() == 0.5)
    }

    @Test func blocksWhenEvidenceContradictsItself() {
        let report = AnswerabilityEngine().assess(
            Question("How many times does the provider gateway retry?"),
            against: [retryFive, retryNone]
        )
        #expect(report.verdict == .contested(aspects: ["times provider gateway retry"]))
    }

    @Test func declinesToRuleOnAQuestionItCouldNotRead() {
        let report = AnswerabilityEngine().assess(Question("What about it?"), against: [cacheTTL])
        #expect(report.verdict == .undetermined(.tooFewAspects(found: 0, required: 1)))
        #expect(report.coverageRate() == nil)
    }

    @Test func declinesToRuleWhenNoEvidenceWasOffered() {
        let report = AnswerabilityEngine().assess(
            Question("What is the time-to-live of the response cache?"),
            against: []
        )
        #expect(report.verdict == .undetermined(.noEvidenceOffered))
        #expect(report.evidenceCount == 0)
    }

    @Test func raisingRequiredCoverageBlocksMore() {
        let question = Question("When was the response cache limit raised during the July migration?")
        let evidence = [cacheTTL, cacheScope]
        #expect(AnswerabilityEngine(policy: .lenient).assess(question, against: evidence).verdict == .answerable)
        #expect(AnswerabilityEngine(policy: .strict).assess(question, against: evidence).verdict
            == .insufficient(missing: ["july migration"]))
    }

    /// The knob that sounds stricter produces fewer refusals, which is the whole reason
    /// both exist. A gate with only `requiredCoverage` refuses what it never understood.
    @Test func raisingMinimumAspectsBlocksLess() {
        let policy = AnswerabilityPolicy(
            requiredCoverage: 0.6,
            supportThreshold: 0.4,
            minimumAspects: 3,
            conflictMargin: 0.2
        )
        let report = AnswerabilityEngine(policy: policy).assess(
            Question("When did the streaming aggregator start dropping frames?"),
            against: [EvidenceItem(id: "doc", text: "The streaming aggregator drops frames when saturated.")]
        )
        #expect(report.verdict == .undetermined(.tooFewAspects(found: 2, required: 3)))
    }

    @Test func aDenialStillCoversTheAspect() {
        let report = AnswerabilityEngine().assess(
            Question("What does the provider gateway retry?"),
            against: [retryNone]
        )
        #expect(report.verdict == .answerable)
        #expect(report.assessments[0].isCovered)
        #expect(report.assessments[0].denyingSources == ["kb-none"])
    }

    @Test func supportBelowTheThresholdIsIgnored() {
        let weak = EvidenceItem(id: "weak", text: "The cache exists.")
        let report = AnswerabilityEngine(policy: .strict).assess(
            Question("What is the streaming aggregator buffer depth limit?"),
            against: [weak]
        )
        #expect(report.assessments[0].affirmingSources.isEmpty)
        #expect(!report.assessments[0].isCovered)
    }

    @Test func lopsidedDisagreementIsNotAConflict() {
        let strong = EvidenceItem(id: "strong", text: "The provider gateway retry ceiling is five.")
        let weak = EvidenceItem(id: "weak", text: "The gateway does not retry.")
        let policy = AnswerabilityPolicy(
            requiredCoverage: 0.5,
            supportThreshold: 0.3,
            minimumAspects: 1,
            conflictMargin: 0.05
        )
        let report = AnswerabilityEngine(policy: policy).assess(
            Question("What is the provider gateway retry ceiling?"),
            against: [strong, weak]
        )
        #expect(!report.assessments[0].isContested)
    }

    @Test func theSeamsCanBeReplacedWithoutTouchingThePolicy() {
        let engine = AnswerabilityEngine(
            policy: .strict,
            extractor: FixedExtractor(result: [subjectAspect(["anything"])]),
            matcher: FixedMatcher(fixed: AspectSupport(strength: 1.0, polarity: .affirms))
        )
        let report = engine.assess(Question("irrelevant"), against: [cacheTTL])
        #expect(report.verdict == .answerable)
    }
}

// MARK: - Report surface

@Suite("Report surface")
struct ReportSurfaceTests {
    private func report(_ verdict: AnswerabilityVerdict) -> AnswerabilityReport {
        AnswerabilityReport(question: Question("Q"), assessments: [], verdict: verdict, evidenceCount: 1)
    }

    @Test func onlyAnApprovedQuestionHasTextToForward() {
        #expect(report(.answerable).approvedQuestion == "Q")
        #expect(report(.insufficient(missing: ["x"])).approvedQuestion == nil)
        #expect(report(.contested(aspects: ["x"])).approvedQuestion == nil)
        #expect(report(.undetermined(.noEvidenceOffered)).approvedQuestion == nil)
    }

    @Test func anUnjudgedQuestionIsReachableOnlyByName() {
        #expect(report(.undetermined(.noEvidenceOffered)).unjudgedQuestion == "Q")
        #expect(report(.answerable).unjudgedQuestion == nil)
    }

    @Test func onlyABlockHasAReason() {
        #expect(report(.answerable).blockingReason == nil)
        #expect(report(.undetermined(.tooFewAspects(found: 0, required: 1))).blockingReason == nil)
        #expect(report(.insufficient(missing: ["a time"])).blockingReason == "no evidence covers: a time")
        #expect(report(.contested(aspects: ["ttl"])).blockingReason == "evidence disagrees about: ttl")
    }

    @Test func valueTypesCarryTheirLabels() {
        #expect(AspectKind.attribute.rawValue == "attribute")
        #expect(Polarity.denies.rawValue == "denies")
        #expect(AttributeProbe.quantity.rawValue == "quantity")
        #expect(AspectSupport.none.strength == 0)
    }
}

// MARK: - Gate

@Suite("Gate statistics")
struct GateTests {
    @Test func anUnusedGateHasNoAbstentionRateRatherThanZero() {
        #expect(GateStatistics().abstentionRate() == nil)
        #expect(GateStatistics().ruled == 0)
    }

    @Test func countsEachVerdictAndExcludesDeclinedRulings() async {
        let gate = AnswerabilityGate()
        let aggregator = EvidenceItem(
            id: "doc-agg",
            text: "The streaming aggregator buffers chunks until the sequence is contiguous."
        )
        await gate.admit(Question("What is the time-to-live of the response cache?"), evidence: [cacheTTL])
        await gate.admit(Question("When did the streaming aggregator drop frames?"), evidence: [aggregator])
        await gate.admit(Question("How many times does the provider gateway retry?"), evidence: [retryFive, retryNone])
        await gate.admit(Question("What about it?"), evidence: [cacheTTL])

        let stats = await gate.statistics()
        #expect(stats.admitted == 1)
        #expect(stats.blockedInsufficient == 1)
        #expect(stats.blockedContested == 1)
        #expect(stats.undetermined == 1)
        #expect(stats.ruled == 3)
        #expect(stats.blocked == 2)
        #expect(abs((stats.abstentionRate() ?? 0) - 2.0 / 3.0) < 1e-9)
    }

    @Test func aGateCanBeGivenItsOwnEngine() async {
        let gate = AnswerabilityGate(engine: AnswerabilityEngine(policy: .strict))
        let report = await gate.admit(Question("What is the response cache?"), evidence: [cacheTTL])
        #expect(report.verdict == .answerable)
    }
}
