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

    public let hotkeyDisplay = "Fn or Option"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelID = defaults.string(forKey: Keys.modelID) ?? "openai_whisper-base"
        autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        showPill = defaults.object(forKey: Keys.showPill) as? Bool ?? true
        formatEnabled = defaults.object(forKey: Keys.formatEnabled) as? Bool ?? false
    }
}

private enum Keys {
    static let modelID = "modelID"
    static let autoPaste = "autoPaste"
    static let restoreClipboard = "restoreClipboard"
    static let showPill = "showPill"
    static let formatEnabled = "formatEnabled"
}
