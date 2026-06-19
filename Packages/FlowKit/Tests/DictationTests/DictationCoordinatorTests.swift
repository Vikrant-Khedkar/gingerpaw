import Audio
import Dictation
import Foundation
import Settings
import TextInsertion
import Transcription
import Testing

@MainActor
@Test
func pressStartsRecording() {
    let coordinator = makeCoordinator()
    coordinator.startRecording()

    if case .recording = coordinator.state {
        #expect(Bool(true))
    } else {
        #expect(Bool(false))
    }
}

@MainActor
@Test
func releaseProcessesAndPastesTranscript() async throws {
    let coordinator = makeCoordinator(transcript: "hello world", insertionOutcome: .pasted)
    coordinator.startRecording()
    coordinator.stopRecordingAndProcess()

    try await waitUntil { coordinator.state == .idle }
    #expect(coordinator.lastResult?.transcript == "hello world")
    #expect(coordinator.lastResult?.insertionOutcome == .pasted)
}

@MainActor
@Test
func transcriptionFailureReturnsFailedState() async throws {
    let coordinator = makeCoordinator(error: StubError.failed)
    coordinator.startRecording()
    coordinator.stopRecordingAndProcess()

    try await waitUntil {
        if case .failed = coordinator.state { return true }
        return false
    }
}

@MainActor
@Test
func copyFallbackIsRecorded() async throws {
    let coordinator = makeCoordinator(transcript: "fallback", insertionOutcome: .copied)
    coordinator.startRecording()
    coordinator.stopRecordingAndProcess()

    try await waitUntil { coordinator.state == .copied }
    #expect(coordinator.lastResult?.insertionOutcome == .copied)
}

@MainActor
private func makeCoordinator(
    transcript: String = "ok",
    insertionOutcome: TextInsertion.InsertionOutcome = .pasted,
    error: Error? = nil
) -> DictationCoordinator {
    DictationCoordinator(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: transcript, error: error),
        inserter: StubInserter(outcome: insertionOutcome),
        settings: FlowSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    )
}

private final class StubRecorder: AudioRecording {
    func start() throws {}
    func stop() throws -> URL { URL(fileURLWithPath: "/tmp/audio.wav") }
    func cancel() {}
}

private struct StubTranscriber: SpeechTranscriber {
    let transcript: String
    let error: Error?

    func transcribe(audioURL _: URL) async throws -> String {
        if let error { throw error }
        return transcript
    }
}

private struct StubInserter: TextInserter {
    let outcome: TextInsertion.InsertionOutcome

    func insert(_: String, restoreClipboard _: Bool) async -> TextInsertion.InsertionOutcome {
        outcome
    }

    func copy(_: String) async -> TextInsertion.InsertionOutcome {
        .copied
    }
}

private enum StubError: Error {
    case failed
}

private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<50 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(Bool(false))
}
