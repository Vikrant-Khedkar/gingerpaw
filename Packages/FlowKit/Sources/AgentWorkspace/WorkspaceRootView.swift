import SwiftUI

/// Tabbed multi-agent workspace: a tab per live agent session (with its logo),
/// a `+` menu to start a new one in a chosen folder, and the selected session's
/// terminal below. Hosted in its own window.
struct WorkspaceRootView: View {
    @State private var model = WorkspaceModel()

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            terminalArea
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear { model.refreshInstalled() }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(model.sessions) { tab($0) }
            addMenu
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background.secondary)
    }

    private func tab(_ session: AgentSession) -> some View {
        let selected = model.selectedID == session.id
        return HStack(spacing: 6) {
            Image(session.kind.logo).resizable().frame(width: 14, height: 14)
            Text(session.folderName).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Button { model.close(session.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = session.id }
    }

    private var addMenu: some View {
        Menu {
            ForEach(AgentKind.allCases) { kind in
                let installed = model.installed.contains(kind)
                Button {
                    if let dir = pickDirectory() { model.open(kind, directory: dir) }
                } label: {
                    Label(installed ? kind.title : "\(kind.title) (not installed)", image: kind.logo)
                }
                .disabled(!installed)
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder private var terminalArea: some View {
        if model.sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 38)).foregroundStyle(.secondary)
                Text("Open an agent session with  +").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ForEach(model.sessions) { session in
                    TerminalHostView(terminal: session.terminal)
                        .opacity(session.id == model.selectedID ? 1 : 0)
                        .allowsHitTesting(session.id == model.selectedID)
                }
            }
        }
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Open Session Here"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
