import SwiftUI

struct DiffLine: Identifiable {
    let id: Int
    let text: String
    let oldLineNo: Int?
    let newLineNo: Int?
}

struct DiffView: View {
    let diff: String

    private var lines: [DiffLine] {
        var result: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        let rawLines = diff.split(separator: "\n", omittingEmptySubsequences: false)

        for (i, line) in rawLines.enumerated() {
            let str = String(line)

            if str.hasPrefix("@@") {
                // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
                if let range = str.range(of: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#, options: .regularExpression) {
                    let match = str[range]
                    let nums = match.split(separator: " ")
                    if nums.count >= 3 {
                        let oldPart = String(nums[1]) // -N or -N,M
                        let newPart = String(nums[2]) // +N or +N,M
                        oldLine = Int(oldPart.dropFirst().split(separator: ",").first ?? "0") ?? 0
                        newLine = Int(newPart.dropFirst().split(separator: ",").first ?? "0") ?? 0
                    }
                }
                result.append(DiffLine(id: i, text: str, oldLineNo: nil, newLineNo: nil))
            } else if str.hasPrefix("diff ") || str.hasPrefix("index ") || str.hasPrefix("---") || str.hasPrefix("+++") || str.hasPrefix("New file:") || str.hasPrefix("Untracked") {
                result.append(DiffLine(id: i, text: str, oldLineNo: nil, newLineNo: nil))
            } else if str.hasPrefix("+") {
                result.append(DiffLine(id: i, text: str, oldLineNo: nil, newLineNo: newLine))
                newLine += 1
            } else if str.hasPrefix("-") {
                result.append(DiffLine(id: i, text: str, oldLineNo: oldLine, newLineNo: nil))
                oldLine += 1
            } else {
                // Context line
                result.append(DiffLine(id: i, text: str, oldLineNo: oldLine, newLineNo: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        return result
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        // Old line number
                        Text(line.oldLineNo.map { String($0) } ?? "")
                            .frame(width: 45, alignment: .trailing)
                            .foregroundStyle(.tertiary)
                        // New line number
                        Text(line.newLineNo.map { String($0) } ?? "")
                            .frame(width: 45, alignment: .trailing)
                            .foregroundStyle(.tertiary)

                        Text("  ")

                        Text(line.text)
                            .foregroundStyle(colorFor(line: line.text))
                    }
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 0.5)
                    .padding(.trailing, 12)
                    .background(backgroundFor(line: line.text))
                }
            }
            .padding(.vertical, 8)
        }
        .textSelection(.enabled)
    }

    private func colorFor(line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") { return .secondary }
        return .primary
    }

    private func backgroundFor(line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        if line.hasPrefix("@@") { return .cyan.opacity(0.05) }
        return .clear
    }
}
