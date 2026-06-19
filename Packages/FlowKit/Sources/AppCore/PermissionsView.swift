import Hotkeys
import Permissions
import SwiftUI

struct PermissionsView: View {
    @Bindable var hotkeyMonitor: RightOptionHotkeyMonitor
    let permissions: PermissionCenter

    @State private var tick = 0
    @State private var showDiagnostics = false
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Permissions", subtitle: "GingerPaw needs these macOS grants to capture and paste.")

            VStack(spacing: 0) {
                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    detail: "Record your voice for transcription.",
                    state: micPermissionState(permissions.microphoneStatus)
                ) {
                    Task { _ = await permissions.requestMicrophone() }
                }
                Divider().padding(.leading, 52)
                permissionRow(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    detail: "Detect the push-to-talk hotkey globally.",
                    state: permissions.inputMonitoringLikelyTrusted ? .granted : .pending
                ) {
                    permissions.requestInputMonitoring()
                    permissions.openInputMonitoringSettings()
                }
                Divider().padding(.leading, 52)
                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Paste text into the focused app.",
                    state: permissions.accessibilityTrusted ? .granted : .pending
                ) {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))

            DisclosureGroup(isExpanded: $showDiagnostics) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Monitor").foregroundStyle(.secondary)
                        Text(hotkeyMonitor.statusText)
                    }
                    GridRow {
                        Text("Last key").foregroundStyle(.secondary)
                        Text(hotkeyMonitor.lastEventText)
                    }
                }
                .font(.system(size: 12))
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Diagnostics").font(.system(size: 13, weight: .semibold))
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))

            Spacer()
        }
        .id(tick)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    @ViewBuilder
    private func permissionRow(icon: String, title: String, detail: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            state.pill
            if state != .granted {
                Button("Grant", action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

extension PermissionState: Equatable {}
