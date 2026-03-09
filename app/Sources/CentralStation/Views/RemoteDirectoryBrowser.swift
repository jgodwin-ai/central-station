import SwiftUI

struct RemoteDirectoryBrowser: View {
    let sshHost: String
    @Binding var selectedPath: String

    @State private var currentPath: String = ""
    @State private var directories: [String] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var pathInput: String = ""
    @State private var isGitRepo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Path input for direct typing
            HStack {
                TextField("Path", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        navigateTo(pathInput)
                    }
                Button("Go") {
                    navigateTo(pathInput)
                }
                .disabled(pathInput.isEmpty)
            }

            // Breadcrumb bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Button("/") { navigateTo("/") }
                        .buttonStyle(.borderless)
                    ForEach(breadcrumbs, id: \.path) { crumb in
                        Text("/").foregroundStyle(.tertiary)
                        Button(crumb.name) { navigateTo(crumb.path) }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
            }

            // Directory list
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    if currentPath != "/" {
                        Button(action: { navigateUp() }) {
                            HStack {
                                Image(systemName: "arrow.turn.up.left")
                                Text("..")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach(directories, id: \.self) { dir in
                        Button(action: { navigateTo(currentPath + "/" + dir) }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(dir)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: 150, maxHeight: 200)
            }

            // Status bar
            HStack {
                if isGitRepo {
                    Label("Git repo", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Select This Directory") {
                    selectedPath = currentPath
                }
                .disabled(currentPath.isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .task {
            if selectedPath.isEmpty {
                if let home = try? await RemoteShell.homeDirectory(host: sshHost) {
                    navigateTo(home)
                } else {
                    navigateTo("/")
                }
            } else {
                navigateTo(selectedPath)
            }
        }
    }

    private struct Breadcrumb: Hashable {
        let name: String
        let path: String
    }

    private var breadcrumbs: [Breadcrumb] {
        let components = currentPath.split(separator: "/").map(String.init)
        var crumbs: [Breadcrumb] = []
        for (i, name) in components.enumerated() {
            let path = "/" + components[0...i].joined(separator: "/")
            crumbs.append(Breadcrumb(name: name, path: path))
        }
        return crumbs
    }

    private func navigateTo(_ path: String) {
        let cleanPath = path.isEmpty ? "/" : path
        isLoading = true
        error = nil
        Task {
            do {
                let dirs = try await RemoteShell.listDirectories(host: sshHost, path: cleanPath)
                let gitCheck = try await RemoteShell.isGitRepo(host: sshHost, path: cleanPath)
                await MainActor.run {
                    currentPath = cleanPath
                    pathInput = cleanPath
                    directories = dirs.sorted()
                    isGitRepo = gitCheck
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Could not list directory: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigateTo(parent.isEmpty ? "/" : parent)
    }
}
