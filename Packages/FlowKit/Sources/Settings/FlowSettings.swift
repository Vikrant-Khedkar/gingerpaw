import Foundation
import Observation

@MainActor
@Observable
public final class FlowSettings {
    public var modelID: String {
        didSet { defaults.set(modelID, forKey: Keys.modelID) }
    }
    public var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }
    public var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) }
    }
    public var showPill: Bool {
        didSet { defaults.set(showPill, forKey: Keys.showPill) }
    }
    public var formatEnabled: Bool {
        didSet { defaults.set(formatEnabled, forKey: Keys.formatEnabled) }
    }
    public var hotkey: Hotkey {
        didSet { defaults.set(hotkey.rawValue, forKey: Keys.hotkey) }
    }
    public var engine: TranscriptionEngine {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }
    public var moonshineModel: MoonshineModel {
        didSet { defaults.set(moonshineModel.rawValue, forKey: Keys.moonshineModel) }
    }

    public var hotkeyDisplay: String { hotkey.display }
    public var engineLabel: String {
        switch engine {
        case .whisperKit: "WhisperKit · \(modelID)"
        case .moonshine: "Moonshine · \(moonshineModel.display)"
        }
    }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelID = defaults.string(forKey: Keys.modelID) ?? "openai_whisper-base"
        autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        showPill = defaults.object(forKey: Keys.showPill) as? Bool ?? true
        formatEnabled = defaults.object(forKey: Keys.formatEnabled) as? Bool ?? false
        hotkey = defaults.string(forKey: Keys.hotkey).flatMap(Hotkey.init) ?? .rightOption
        engine = defaults.string(forKey: Keys.engine).flatMap(TranscriptionEngine.init) ?? .whisperKit
        moonshineModel = defaults.string(forKey: Keys.moonshineModel).flatMap(MoonshineModel.init) ?? .base
    }
}

private enum Keys {
    static let modelID = "modelID"
    static let autoPaste = "autoPaste"
    static let restoreClipboard = "restoreClipboard"
    static let showPill = "showPill"
    static let formatEnabled = "formatEnabled"
    static let hotkey = "hotkey"
    static let engine = "engine"
    static let moonshineModel = "moonshineModel"
}
