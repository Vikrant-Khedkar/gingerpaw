import AVFoundation
import AppKit
import Dictation
import SwiftUI

enum Brand {
    /// GingerFlow violet accent — violet-500 in light, violet-400 in dark.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xA3 / 255, green: 0x7C / 255, blue: 0xEF / 255, alpha: 1)
            : NSColor(srgbRed: 0x87 / 255, green: 0x49 / 255, blue: 0xD2 / 255, alpha: 1)
    })
}

enum FlowSection: String, CaseIterable, Identifiable {
    case dictate = "Dictate"
    case lab = "Lab"
    case permissions = "Permissions"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dictate: "waveform"
        case .lab: "testtube.2"
        case .permissions: "lock.shield"
        case .settings: "gearshape"
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
    }
}

extension DictationState {
    var label: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording"
        case .processing: "Transcribing"
        case .inserting: "Pasting"
        case .copied: "Copied to clipboard"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .secondary
        case .recording: .red
        case .processing, .inserting: .orange
        case .copied: .green
        case .failed: .red
        }
    }

    var glyph: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .processing, .inserting: "waveform"
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum PermissionState {
    case granted, denied, pending

    var pill: StatusPill {
        switch self {
        case .granted: StatusPill(text: "Allowed", color: .green)
        case .denied: StatusPill(text: "Denied", color: .red)
        case .pending: StatusPill(text: "Not granted", color: .orange)
        }
    }
}

func micPermissionState(_ status: AVAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorized: .granted
    case .denied, .restricted: .denied
    default: .pending
    }
}
