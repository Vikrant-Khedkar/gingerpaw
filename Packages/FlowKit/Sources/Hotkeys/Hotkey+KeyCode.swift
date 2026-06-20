import CoreGraphics
import Settings

extension Hotkey {
    /// Hardware keycode for the modifier (from `.flagsChanged` events).
    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        case .fn: 63
        case .rightCommand: 54
        }
    }

    /// The modifier flag that is set while the key is held.
    var flag: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: .maskAlternate
        case .fn: .maskSecondaryFn
        case .rightCommand: .maskCommand
        }
    }
}
