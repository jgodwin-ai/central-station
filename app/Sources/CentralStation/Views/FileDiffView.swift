import SwiftUI

struct FileDiffView: View {
    let task: AppTask
    @State private var changedFiles: [WorktreeManager.ChangedFile] = []
    @State private var selectedFile: WorktreeManager.ChangedFile?
    @State private var fileDiff: String?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // File list (20%)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Changed Files")
                            .font(.headline)
                        Spacer()
                        Button(action: refresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)

                    Divider()

                    if changedFiles.isEmpty {
                        ContentUnavailableView(
                            "No Changes",
                            systemImage: "doc.text",
                            description: Text("Click Refresh to check for changes")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        List(changedFiles, selection: Binding(
                            get: { selectedFile?.id },
                            set: { id in
                                selectedFile = changedFiles.first { $0.id == id }
                                if let file = selectedFile {
                                    loadFileDiff(file)
                                }
                            }
                        )) { file in
                            HStack(spacing: 8) {
                                statusBadge(for: file.status)
                                Text(file.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(file.id)
                        }
                        .listStyle(.sidebar)
                    }
                }
                .frame(width: geo.size.width * 0.2)

                Divider()

                // Diff content (80%)
                VStack(spacing: 0) {
                    if let file = selectedFile {
                        HStack {
                            statusBadge(for: file.status)
                            Text(file.path)
                                .font(.system(.body, design: .monospaced).bold())
                            Spacer()
                        }
                        .padding(8)
                        .background(.bar)

                        Divider()

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let diff = fileDiff {
                            DiffView(diff: diff)
                        }
                    } else {
                        ContentUnavailableView(
                            "Select a File",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Choose a file from the list to view its diff")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        Task {
            changedFiles = await WorktreeManager.getChangedFiles(worktreePath: task.worktreePath)
            if let sel = selectedFile, !changedFiles.contains(where: { $0.id == sel.id }) {
                selectedFile = nil
                fileDiff = nil
            }
        }
    }

    private func loadFileDiff(_ file: WorktreeManager.ChangedFile) {
        isLoading = true
        Task {
            fileDiff = await WorktreeManager.getFileDiff(worktreePath: task.worktreePath, filePath: file.path)
            isLoading = false
        }
    }

    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "M": ("M", .orange)
        case "A": ("A", .green)
        case "D": ("D", .red)
        case "??": ("N", .blue)
        default: (status, .gray)
        }
        Text(label)
            .font(.caption.bold().monospaced())
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
