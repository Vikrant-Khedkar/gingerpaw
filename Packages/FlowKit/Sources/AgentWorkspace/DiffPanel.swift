import SwiftUI

/// Right-hand panel: changed files in the workspace's worktree (grouped by dir,
/// with +/− counts) and a unified diff for the selected file.
struct DiffPanel: View {
    let workspace: Workspace
    @State private var mode = 0 // 0 = Files, 1 = Diff

    private var grouped: [(String, [FileChange])] {
        Dictionary(grouping: workspace.changes, by: \.dir)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $mode) {
                    Text("Files").tag(0)
                    Text("Diff").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer(minLength: 6)
                Text("\(workspace.changes.count) changed")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                Button { workspace.refreshDiff() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            if mode == 0 { filesList } else { diffView }
        }
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
    }

    @ViewBuilder private var filesList: some View {
        if workspace.changes.isEmpty {
            placeholder("checkmark.circle", "No changes yet")
        } else {
            List {
                ForEach(grouped, id: \.0) { dir, files in
                    Section(header: Text(dir.isEmpty ? "/" : dir).font(.system(size: 10)).foregroundStyle(.secondary)) {
                        ForEach(files) { file in
                            Button { workspace.selectFile(file); mode = 1 } label: { fileRow(file) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func fileRow(_ file: FileChange) -> some View {
        HStack(spacing: 8) {
            Text(file.status)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(width: 14, height: 14)
                .background(statusColor(file.status).opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(statusColor(file.status))
            Text(file.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 6)
            if file.insertions > 0 { Text("+\(file.insertions)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.green) }
            if file.deletions > 0 { Text("−\(file.deletions)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.red) }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var diffView: some View {
        if workspace.fileDiff.isEmpty {
            placeholder("doc.text", workspace.selectedFile == nil ? "Select a file" : "No diff")
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workspace.fileDiff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : String(line))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineColor(String(line)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
        }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(_ s: String) -> Color {
        switch s { case "A", "?": .green; case "D": .red; case "R": .purple; default: .orange }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        return .primary
    }
}
