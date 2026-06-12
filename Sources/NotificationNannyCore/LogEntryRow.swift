import SwiftUI

struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            if entry.level != .info {
                Text(entry.level.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(entry.level == .warn ? Color.orange : Color(red: 1, green: 0.3, blue: 0.3),
                                in: Capsule())
            }
            if !entry.tag.isEmpty {
                Text(entry.tag)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tagColor(entry.tag).opacity(0.9))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(tagColor(entry.tag).opacity(0.15), in: Capsule())
            }
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.78))
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "AX":     return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "Banner": return Color.nannyAccent
        case "Custom": return Color(red: 0.2, green: 0.8, blue: 0.7)
        case "System": return Color(white: 0.6)
        case "Test":   return Color(red: 0.3, green: 0.9, blue: 0.4)
        default:       return Color(white: 0.55)
        }
    }
}
