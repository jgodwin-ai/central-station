import SwiftUI

struct PopOutTerminalView: View {
    let task: AppTask
    let coordinator: TaskCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: task.status.icon)
                    .foregroundStyle(task.status.color)
                Text(task.id)
                    .font(.headline)
                Text("— \(task.description)")
                    .foregroundStyle(.secondary)
                Spacer()

                Button(action: dockBack) {
                    Label("Dock Back", systemImage: "rectangle.portrait.and.arrow.right.fill")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            .padding(8)
            .background(.bar)

            Divider()

            if task.status == .waitingForInput {
                HStack {
                    Image(systemName: "exclamationmark.bubble.fill")
                    Text("This task needs your input")
                        .font(.callout.bold())
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)

                Divider()
            }

            EmbeddedTerminalView(task: task, onProcessExit: {
                task.status = .completed
            })
        }
        .navigationTitle("CS: \(task.id)")
    }

    private func dockBack() {
        coordinator.poppedOutTaskIds.remove(task.id)
        dismiss()
    }
}
