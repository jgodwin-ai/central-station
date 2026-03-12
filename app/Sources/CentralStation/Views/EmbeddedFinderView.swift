import SwiftUI
import AppKit

/// An embedded file browser for the worktree directory.
/// For local tasks, reads from disk directly. For remote tasks, lists via SSH.
struct EmbeddedFinderView: View {
    let task: AppTask

    @State private var files: [FileEntry] = []
    @State private var currentPath: String = ""
    @State private var isLoading = false
    @State private var error: String?

    struct FileEntry: Identifiable, Hashable {
        let id: String
        let name: String
        let isDirectory: Bool
        let size: String
        let icon: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb / path bar
            HStack {
                Button(action: { navigateTo(task.worktreePath) }) {
                    Image(systemName: "house")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Worktree root")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(breadcrumbs, id: \.path) { crumb in
                            if crumb.path != breadcrumbs.first?.path {
                                Text("/").foregroundStyle(.tertiary).font(.caption)
                            }
                            Button(crumb.name) { navigateTo(crumb.path) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }

                Spacer()

                Button(action: { navigateTo(currentPath) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                if !task.isRemote {
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: currentPath))
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Finder")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if currentPath != task.worktreePath {
                        Button(action: { navigateUp() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.up.left")
                                    .frame(width: 20)
                                    .foregroundStyle(.secondary)
                                Text("..")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                    }

                    ForEach(files) { file in
                        Button(action: { fileAction(file) }) {
                            HStack(spacing: 8) {
                                Image(systemName: file.icon)
                                    .frame(width: 20)
                                    .foregroundStyle(file.isDirectory ? .blue : .secondary)
                                Text(file.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if !file.isDirectory {
                                    Text(file.size)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                                if file.isDirectory {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { navigateTo(task.worktreePath) }
    }

    private struct Breadcrumb: Hashable {
        let name: String
        let path: String
    }

    private var breadcrumbs: [Breadcrumb] {
        let root = task.worktreePath
        guard currentPath.hasPrefix(root) else { return [] }
        let relative = String(currentPath.dropFirst(root.count))
        let components = relative.split(separator: "/").map(String.init)

        var crumbs = [Breadcrumb(name: (root as NSString).lastPathComponent, path: root)]
        for (i, name) in components.enumerated() {
            let path = root + "/" + components[0...i].joined(separator: "/")
            crumbs.append(Breadcrumb(name: name, path: path))
        }
        return crumbs
    }

    private func navigateTo(_ path: String) {
        isLoading = true
        error = nil
        Task {
            do {
                let entries: [FileEntry]
                if let host = task.sshHost {
                    entries = try await listRemote(host: host, path: path)
                } else {
                    entries = try listLocal(path: path)
                }
                await MainActor.run {
                    currentPath = path
                    files = entries
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        if parent.hasPrefix(task.worktreePath) || parent == task.worktreePath {
            navigateTo(parent)
        } else {
            navigateTo(task.worktreePath)
        }
    }

    private func fileAction(_ file: FileEntry) {
        if file.isDirectory {
            navigateTo(currentPath + "/" + file.name)
        } else if !task.isRemote {
            NSWorkspace.shared.open(URL(fileURLWithPath: currentPath + "/" + file.name))
        }
    }

    // MARK: - Local file listing

    private func listLocal(path: String) throws -> [FileEntry] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: path)
        return contents
            .filter { !$0.hasPrefix(".") }
            .sorted { lhs, rhs in
                let lhsIsDir = isLocalDirectory(path: path + "/" + lhs)
                let rhsIsDir = isLocalDirectory(path: path + "/" + rhs)
                if lhsIsDir != rhsIsDir { return lhsIsDir }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { name in
                let fullPath = path + "/" + name
                let isDir = isLocalDirectory(path: fullPath)
                let size = isDir ? "" : localFileSize(path: fullPath)
                return FileEntry(
                    id: name,
                    name: name,
                    isDirectory: isDir,
                    size: size,
                    icon: iconForFile(name: name, isDirectory: isDir)
                )
            }
    }

    private func isLocalDirectory(path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func localFileSize(path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: - Remote file listing

    private func listRemote(host: String, path: String) async throws -> [FileEntry] {
        let escaped = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // ls -lAp: long format, almost-all (skip . and ..), append / to dirs
        let output = try await RemoteShell.run(host: host, command: "ls -lAp \(escaped) 2>/dev/null")
        var entries: [FileEntry] = []
        for line in output.split(separator: "\n").dropFirst() { // skip "total N" line
            let str = String(line)
            // Parse ls -l output: permissions links owner group size month day time name
            let parts = str.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            let name = String(parts[8]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let isDir = str.hasPrefix("d")
            let sizeStr = isDir ? "" : formatRemoteSize(String(parts[4]))
            guard !name.hasPrefix(".") else { continue }
            entries.append(FileEntry(
                id: name,
                name: name,
                isDirectory: isDir,
                size: sizeStr,
                icon: iconForFile(name: name, isDirectory: isDir)
            ))
        }
        // Sort: directories first, then alphabetical
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func formatRemoteSize(_ sizeStr: String) -> String {
        guard let bytes = Int64(sizeStr) else { return sizeStr }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - File icons

    private func iconForFile(name: String, isDirectory: Bool) -> String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go", "rs", "c", "cpp", "h", "m", "java", "rb", "kt":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "doc.badge.gearshape"
        case "md", "txt", "rtf":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "ico", "webp":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "zip", "tar", "gz", "bz2", "xz":
            return "doc.zipper"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}
