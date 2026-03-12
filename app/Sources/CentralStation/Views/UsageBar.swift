import SwiftUI

struct UsageBar: View {
    let label: String
    let percent: Double
    let resetIn: String?

    private var barColor: Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f%%", percent))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            if let resetIn {
                Text(resetIn)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
