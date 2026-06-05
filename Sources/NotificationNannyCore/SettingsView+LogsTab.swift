import SwiftUI
import AppKit

struct LogsTabView: View {
    @ObservedObject private var logger = NannyLogger.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent activity from the notification repositioner. Useful for diagnosing issues — share the saved file in a bug report.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("\(logger.entries.count) entries")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color(white: 0.45))
                Spacer()
                Button("Clear") { logger.clear() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
                Button("Save…") { saveLog() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if logger.entries.isEmpty {
                        Text("No entries yet. Trigger a notification to start logging.")
                            .font(.caption2).foregroundStyle(.tertiary).padding(10)
                    } else {
                        ForEach(logger.entries.reversed()) { entry in
                            logEntryRow(entry)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.38))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            if entry.level != .info {
                Text(entry.level.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.level == .warn ? Color.orange : Color.red)
                    .frame(width: 38, alignment: .leading)
            } else {
                Color.clear.frame(width: 38, height: 1)
            }
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.78))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
    }

    private func saveLog() {
        let text = logger.exportText()
        guard let data = text.data(using: .utf8) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NotificationNanny Log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
