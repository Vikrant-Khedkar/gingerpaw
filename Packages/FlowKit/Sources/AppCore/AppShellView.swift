import AgentWorkspace
import Dictation
import Hotkeys
import Permissions
import Settings
import SwiftUI

public struct AppShellView: View {
    @Bindable private var coordinator: DictationCoordinator
    @Bindable private var hotkeyMonitor: RightOptionHotkeyMonitor
    @Bindable private var settings: FlowSettings
    private let permissions: PermissionCenter

    @State private var selection: FlowSection = .dictate

    public init(coordinator: DictationCoordinator, hotkeyMonitor: RightOptionHotkeyMonitor, settings: FlowSettings, permissions: PermissionCenter) {
        self.coordinator = coordinator
        self.hotkeyMonitor = hotkeyMonitor
        self.settings = settings
        self.permissions = permissions
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Brand.accent)
                    Text("GingerPaw").font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 14)

                ForEach(FlowSection.allCases) { section in
                    sidebarItem(section)
                }

                Spacer()

                Text(permissions.inputMonitoringLikelyTrusted ? "Hotkey active" : "Hotkey off")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selection {
                case .dictate:
                    DictateView(coordinator: coordinator, settings: settings, hotkeyReady: permissions.inputMonitoringLikelyTrusted)
                case .voice:
                    VoiceView()
                case .workspaces:
                    EmptyView() // opens in its own window
                case .permissions:
                    PermissionsView(hotkeyMonitor: hotkeyMonitor, permissions: permissions)
                case .settings:
                    SettingsView(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(selection == .workspaces ? 0 : 28)
        }
        .frame(minWidth: 660, minHeight: 460)
        .tint(Brand.accent)
    }

    private func sidebarItem(_ section: FlowSection) -> some View {
        let isSelected = selection == section
        return Button {
            if section == .workspaces {
                AgentWorkspaceWindow.show()
            } else {
                selection = section
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Brand.accent : Color.secondary)
                Text(section.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Brand.accent : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Brand.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
