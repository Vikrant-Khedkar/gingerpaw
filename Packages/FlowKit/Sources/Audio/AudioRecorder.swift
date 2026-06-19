import AVFoundation
import Foundation

@MainActor
public final class AudioRecorder: NSObject, AudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    public override init() {}

    public func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowoss-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let nextRecorder = try AVAudioRecorder(url: url, settings: settings)
        nextRecorder.delegate = self
        nextRecorder.isMeteringEnabled = true
        guard nextRecorder.record() else {
            throw AudioRecordingError.startFailed
        }
        outputURL = url
        recorder = nextRecorder
    }

    public func stop() throws -> URL {
        guard let recorder, let outputURL else {
            throw AudioRecordingError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }

    public func cancel() {
        recorder?.stop()
        recorder = nil
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
    }
}

public enum AudioRecordingError: Error {
    case startFailed
    case notRecording
}
