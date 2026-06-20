import AVFoundation
import Audio
import Foundation
import Observation
import Settings
import TextInsertion
import Transcription

@MainActor
@Observable
public final class DictationCoordinator {
    public private(set) var state: DictationState = .idle
    public private(set) var lastResult: DictationResult?
    public private(set) var history: [DictationResult] = []
    public private(set) var lastError: String?
    public var onStateChange: (@MainActor (DictationState) -> Void)?

    private let recorder: AudioRecording
    private let transcriber: SpeechTranscriber
    private let inserter: TextInserter
    private let processor: TextProcessor?
    private let settings: FlowSettings
    private var startedAt: Date?

    public init(
        recorder: AudioRecording,
        transcriber: SpeechTranscriber,
        inserter: TextInserter,
        settings: FlowSettings,
        processor: TextProcessor? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.inserter = inserter
        self.processor = processor
        self.settings = settings
    }

    public func startRecording() {
        guard state.canStartRecording else { return }
        do {
            let now = Date()
            startedAt = now
            try recorder.start()
            lastError = nil
            setState(.recording(startedAt: now))
        } catch {
            fail(error)
        }
    }

    public func stopRecordingAndProcess() {
        guard case .recording = state else { return }
        setState(.processing)

        Task {
            do {
                let audioURL = try recorder.stop()
                let audioSeconds = Self.audioDuration(audioURL)
                let transcribeStart = Date()
                let transcript = try await transcriber.transcribe(audioURL: audioURL).trimmingCharacters(in: .whitespacesAndNewlines)
                let transcribeSeconds = Date().timeIntervalSince(transcribeStart)
                guard !transcript.isEmpty else {
                    // silence / non-speech — quietly do nothing, don't paste or flag a failure
                    startedAt = nil
                    setState(.idle)
                    return
                }

                let finalText = await structure(transcript)

                setState(.inserting)
                let outcome = await insert(finalText)
                let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
                let result = DictationResult(
                    transcript: finalText,
                    duration: duration,
                    modelID: settings.modelID,
                    insertionOutcome: outcome,
                    engineLabel: settings.engineLabel,
                    audioSeconds: audioSeconds,
                    transcribeSeconds: transcribeSeconds
                )
                lastResult = result
                history.insert(result, at: 0)
                if history.count > 20 { history.removeLast() }
                setState(outcome == .pasted ? .idle : .copied)
                if outcome != .pasted {
                    resetIdleSoon()
                }
                startedAt = nil
            } catch {
                fail(error)
            }
        }
    }

    public func cancelRecording() {
        recorder.cancel()
        startedAt = nil
        setState(.idle)
    }

    private static func audioDuration(_ url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private func structure(_ transcript: String) async -> String {
        guard settings.formatEnabled, let processor else { return transcript }
        do {
            return try await processor.format(transcript)
        } catch {
            return transcript
        }
    }

    private func insert(_ transcript: String) async -> InsertionOutcome {
        guard settings.autoPaste else {
            return await inserter.copy(transcript)
        }
        return await inserter.insert(transcript, restoreClipboard: settings.restoreClipboard)
    }

    private func fail(_ error: Error) {
        recorder.cancel()
        let message = String(describing: error)
        lastError = message
        startedAt = nil
        setState(.failed(message))
        resetIdleSoon()
    }

    private func setState(_ next: DictationState) {
        state = next
        onStateChange?(next)
    }

    private func resetIdleSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if state == .copied {
                setState(.idle)
            } else if case .failed = state {
                setState(.idle)
            }
        }
    }
}

public enum DictationError: Error, Equatable {
    case emptyTranscript
}

private extension DictationState {
    var canStartRecording: Bool {
        switch self {
        case .idle, .copied, .failed:
            true
        case .recording, .processing, .inserting:
            false
        }
    }
}
