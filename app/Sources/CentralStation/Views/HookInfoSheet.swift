import SwiftUI

struct HookInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let port: UInt16
    let isInstalled: Bool
    let onInstall: () -> Void
    @State private var showSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hook Status")
                .font(.title2.bold())

            if isInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("Hooks installed")
                        .font(.headline)
                }
                Text("Hook server running on port \(port). Claude Code sessions will report status changes and permission requests.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Reinstall Hooks") {
                        onInstall()
                        showSuccess = true
                    }
                    .buttonStyle(.bordered)
                    .help("Force reinstall hooks to ~/.claude/settings.json")

                    if showSuccess {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showSuccess)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    Text("Hooks not installed")
                        .font(.headline)
                }
                Text("Install hooks to ~/.claude/settings.json so Claude Code reports status changes and permission requests to Claude Central Station.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Install Hooks") {
                        onInstall()
                        showSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if showSuccess {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showSuccess)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Hooks:")
                    .font(.caption.bold())
                VStack(alignment: .leading, spacing: 2) {
                    Label("**UserPromptSubmit** — notifies when user sends a message", systemImage: "play.circle")
                    Label("**Stop** — notifies when Claude finishes a turn", systemImage: "pause.circle")
                    Label("**Notification** — catches permission prompts, idle, and questions", systemImage: "bell")
                    Label("**PermissionRequest** — notifies on tool permission requests", systemImage: "lock.shield")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 440, height: isInstalled ? 320 : 350)
    }
}
