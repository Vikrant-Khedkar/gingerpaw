import TextInsertion
import Testing

@Test
func insertionOutcomeValuesAreStable() {
    #expect(InsertionOutcome.pasted == .pasted)
    #expect(InsertionOutcome.copied == .copied)
    #expect(InsertionOutcome.failed == .failed)
}
