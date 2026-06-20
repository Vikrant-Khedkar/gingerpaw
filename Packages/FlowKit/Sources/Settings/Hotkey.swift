import Foundation

/// The push-to-talk key the user holds to dictate. Modifier keys only — they're
/// the natural fit for hold-to-talk and don't collide with normal typing.
public enum Hotkey: String, CaseIterable, Sendable, Identifiable {
    case rightOption
    case leftOption
    case fn
    case rightCommand

    public var id: String { rawValue }

    public var display: String {
        switch self {
        case .rightOption: "Right Option (⌥)"
        case .leftOption: "Left Option (⌥)"
        case .fn: "Fn / Globe (🌐)"
        case .rightCommand: "Right Command (⌘)"
        }
    }
}
