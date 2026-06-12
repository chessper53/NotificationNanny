import SwiftUI
import AppKit

struct LogsTabView: View {
    @ObservedObject private var logger = NannyLogger.shared

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
                Button("Save…") { logger.saveToFile() }
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
                            LogEntryRow(entry: entry)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
