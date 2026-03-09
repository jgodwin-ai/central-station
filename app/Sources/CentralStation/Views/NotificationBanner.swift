import SwiftUI

struct NotificationBanner: View {
    let count: Int
    let tasks: [AppTask]

    private var waitingTasks: [AppTask] {
        tasks.filter { $0.status == .waitingForInput }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(.orange)
                Text("\(count) task\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") input")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ForEach(waitingTasks) { task in
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text(task.id)
                        .font(.caption)
                        .bold()
                    if let msg = task.lastMessage {
                        Text("— " + msg.prefix(40) + (msg.count > 40 ? "…" : ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 6)
        }
        .background(.orange.opacity(0.08))
    }
}
