import SwiftUI

struct ManageRemotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let remoteStore: RemoteStore

    @State private var editingRemote: RemoteConfig?
    @State private var showAddForm = false
    @State private var testResult: (id: String, success: Bool, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Remotes")
                .font(.title2.bold())

            if remoteStore.remotes.isEmpty && !showAddForm {
                VStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No saved remotes")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                List {
                    ForEach(remoteStore.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.alias).font(.headline)
                                Text(remote.sshHost)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let dir = remote.defaultDirectory {
                                    Text(dir)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if let result = testResult, result.id == remote.id {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                    .help(result.message)
                            }

                            Button("Test") {
                                Task {
                                    let result = await remoteStore.testConnection(remote: remote)
                                    switch result {
                                    case .success(let msg):
                                        testResult = (remote.id, true, msg)
                                    case .failure(let err):
                                        testResult = (remote.id, false, err.localizedDescription)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                remoteStore.delete(remote)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 120)
            }

            if showAddForm || editingRemote != nil {
                RemoteFormView(
                    remote: editingRemote,
                    onSave: { remote in
                        if editingRemote != nil {
                            remoteStore.update(remote)
                        } else {
                            remoteStore.add(remote)
                        }
                        editingRemote = nil
                        showAddForm = false
                    },
                    onCancel: {
                        editingRemote = nil
                        showAddForm = false
                    }
                )
            }

            HStack {
                Button("Add Remote") { showAddForm = true }
                    .disabled(showAddForm)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 480, maxWidth: 480, minHeight: 300)
    }
}

struct RemoteFormView: View {
    let remote: RemoteConfig?
    let onSave: (RemoteConfig) -> Void
    let onCancel: () -> Void

    @State private var alias: String = ""
    @State private var sshHost: String = ""

    var body: some View {
        GroupBox("New Remote") {
            Form {
                TextField("Alias", text: $alias, prompt: Text("e.g. Dev Server"))
                    .textFieldStyle(.roundedBorder)
                TextField("SSH Host", text: $sshHost, prompt: Text("e.g. user@10.0.1.5 or devbox"))
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    let config = RemoteConfig(
                        id: remote?.id ?? UUID().uuidString.lowercased(),
                        alias: alias,
                        sshHost: sshHost,
                        defaultDirectory: remote?.defaultDirectory
                    )
                    onSave(config)
                }
                .disabled(alias.isEmpty || sshHost.isEmpty)
            }
            .padding(.top, 4)
        }
        .onAppear {
            if let remote {
                alias = remote.alias
                sshHost = remote.sshHost
            }
        }
    }
}
