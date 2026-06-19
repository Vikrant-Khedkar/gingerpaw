import Foundation
import WhisperKit

public actor WhisperKitTranscriber: SpeechTranscriber {
    private let modelIDProvider: @Sendable () async -> String
    private var pipelines: [String: WhisperKit] = [:]

    public init(modelID: String = "small") {
        self.modelIDProvider = { modelID }
    }

    public init(modelIDProvider: @escaping @Sendable () async -> String) {
        self.modelIDProvider = modelIDProvider
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let modelID = await modelIDProvider()
        let pipe = try await loadPipeline(modelID: modelID)
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        return results.map(\.text).joined(separator: " ")
    }

    private func loadPipeline(modelID: String) async throws -> WhisperKit {
        if let pipeline = pipelines[modelID] {
            return pipeline
        }
        let config: WhisperKitConfig
        if let bundled = Self.bundledModelFolder(modelID) {
            // ship-with-app: load the CoreML model straight from the bundle, no download
            config = WhisperKitConfig(modelFolder: bundled.path, load: true)
        } else {
            config = WhisperKitConfig(model: modelID, modelRepo: "argmaxinc/whisperkit-coreml")
        }
        let next = try await WhisperKit(config)
        pipelines[modelID] = next
        return next
    }

    private static func bundledModelFolder(_ modelID: String) -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let url = base.appending(path: "Models/whisper/\(modelID)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
