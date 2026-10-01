import AppKit
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
                .foregroundStyle(Color.nannyMuted(0.35))
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
                .foregroundStyle(Color.nannyAdaptive(light: .labelColor, dark: NSColor(white: 0.78, alpha: 1)))
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
    }

    // Light variants are darker shades of the same hues: the dark ones are tuned to
    // glow on a near black log and wash out to almost nothing on a light one.
    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "AX":     return hue(light: (0.10, 0.36, 0.85), dark: (0.4, 0.6, 1.0))
        case "Banner": return Color.nannyAccent
        case "Custom": return hue(light: (0.0, 0.50, 0.45), dark: (0.2, 0.8, 0.7))
        case "System": return Color.nannyMuted(0.6)
        case "Test":   return hue(light: (0.10, 0.52, 0.20), dark: (0.3, 0.9, 0.4))
        default:       return Color.nannyMuted(0.55)
        }
    }

    private func hue(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color.nannyAdaptive(light: NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1),
                            dark: NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1))
    }
}
