import SwiftUI

/// Right-hand panel ("Trail" style): Files / Changes / Review tabs, dir-grouped
/// changed files, a tinted unified diff, and a footer with the commit action.
struct DiffPanel: View {
    let workspace: Workspace
    @State private var tab = 0 // 0 Files, 1 Changes
    @State private var showCommit = false
    @State private var commitMessage = ""
    @State private var committing = false

    private var grouped: [(String, [FileChange])] {
        Dictionary(grouping: workspace.changes, by: \.dir)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WS.border)
            if tab == 0 { filesList } else { changesView }
            footer
        }
        .frame(maxHeight: .infinity)
        .background(WS.panel)
        .overlay(alignment: .leading) { Rectangle().fill(WS.border).frame(width: 1) }
        .sheet(isPresented: $showCommit) { commitSheet }
    }

    private var header: some View {
        HStack(spacing: 18) {
            tabLabel("Files", 0)
            tabLabel("Changes", 1)
            Text("Review").font(.system(size: 13)).foregroundStyle(WS.textDim)
            Spacer()
            Button { workspace.refreshDiff() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(WS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private func tabLabel(_ title: String, _ idx: Int) -> some View {
        let on = tab == idx
        return Text(title)
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? WS.textPrimary : WS.textSecondary)
            .frame(height: 42)
            .overlay(alignment: .bottom) { if on { Rectangle().fill(WS.accent).frame(height: 2) } }
            .contentShape(Rectangle())
            .onTapGesture { tab = idx }
    }

    @ViewBuilder private var filesList: some View {
        if workspace.changes.isEmpty {
            placeholder("checkmark.circle", "No changes yet")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.0) { dir, files in
                        Text(dir.isEmpty ? "/" : dir)
                            .font(WS.mono(10.5, .semibold)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(WS.label)
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                        ForEach(files) { fileRow($0) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func fileRow(_ file: FileChange) -> some View {
        let selected = workspace.selectedFile == file.path
        return HStack(spacing: 9) {
            Image(systemName: "doc").font(.system(size: 12))
                .foregroundStyle(selected ? WS.accent : WS.textTertiary)
            Text(file.name).font(.system(size: 12.5))
                .foregroundStyle(selected ? WS.textPrimary : Color(hex: 0xd7d8db)).lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                if file.insertions > 0 { Text("+\(file.insertions)").foregroundStyle(WS.add) }
                Text("−\(file.deletions)").foregroundStyle(file.deletions > 0 ? WS.del : WS.textTertiary)
            }.font(WS.mono(11))
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(selected ? WS.rowSelected : .clear)
        .contentShape(Rectangle())
        .onTapGesture { workspace.selectFile(file); tab = 1 }
    }

    @ViewBuilder private var changesView: some View {
        if workspace.fileDiff.isEmpty {
            placeholder("doc.text", workspace.selectedFile == nil ? "Select a file" : "No diff")
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workspace.fileDiff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                        let line = String(raw)
                        Text(line.isEmpty ? " " : line)
                            .font(WS.mono(11.5)).foregroundStyle(lineColor(line))
                            .padding(.horizontal, 12).padding(.vertical, 0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(lineBg(line))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            (Text("\(workspace.changes.count) files · ")
                + Text("+\(workspace.diff.insertions)").foregroundColor(WS.add)
                + Text(" −\(workspace.diff.deletions)").foregroundColor(WS.del))
                .font(WS.mono(11)).foregroundStyle(WS.textTertiary)
            Spacer()
            Button { commitMessage = ""; showCommit = true } label: { Text("Commit…") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(workspace.changes.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private var commitSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Commit changes").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
            Text("\(workspace.changes.count) files in \(workspace.branch)").font(WS.mono(11)).foregroundStyle(WS.textTertiary)
            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(WS.textPrimary).lineLimit(3...6)
                .padding(10).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
            HStack {
                Spacer()
                Button("Cancel") { showCommit = false }.buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                Button(committing ? "Committing…" : "Commit") { commit() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || committing)
            }
        }
        .padding(20).frame(width: 420).background(Color(hex: 0x26272d))
    }

    private func commit() {
        committing = true
        let msg = commitMessage
        Task {
            do { try await workspace.commit(message: msg); committing = false; showCommit = false }
            catch { committing = false; showCommit = false }
        }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(WS.textDim)
            Text(text).font(.system(size: 12)).foregroundStyle(WS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color(hex: 0x86d191) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color(hex: 0xe58a90) }
        if line.hasPrefix("@@") { return WS.label }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") { return WS.textTertiary }
        return WS.textSecondary
    }

    private func lineBg(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return WS.add.opacity(0.10) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return WS.del.opacity(0.10) }
        if line.hasPrefix("@@") { return WS.accent.opacity(0.07) }
        return .clear
    }
}
