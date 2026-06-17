import SwiftUI
import AppKit

/// Diagnostics & developer tools: health checks, the activity log, and tools for reproducing /
/// inspecting notification edge cases. The single place to gather everything for a bug report.
struct DebugTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin
    @ObservedObject private var logger = NannyLogger.shared

    @State private var diagItems: [DiagItem] = []
    @State private var diagCopied = false
    @State private var burstCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Diagnostics (expanded by default — the first thing you want for a report)
            CollapsibleSection(title: "Diagnostics", systemImage: "stethoscope", initiallyExpanded: true) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Diagnostics.fullReport(diagItems), forType: .string)
                    diagCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { diagCopied = false }
                } label: {
                    Label(diagCopied ? "Copied!" : "Copy Report",
                          systemImage: diagCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless).font(.caption)
                .foregroundStyle(diagCopied ? .green : Color.nannyAccent)
                .animation(.easeInOut(duration: 0.15), value: diagCopied)
                Button { refreshDiagnostics() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent).help("Refresh")
            } content: {
                VStack(spacing: 0) {
                    ForEach(diagItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.status.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.status.color)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label).font(.caption.weight(.medium)).foregroundStyle(.primary)
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        if item.id != diagItems.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            // MARK: Activity log
            CollapsibleSection(title: "Activity log", systemImage: "doc.text.magnifyingglass") {
                Text("\(logger.entries.count)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Button("Clear") { logger.clear() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
                Button("Save…") { logger.saveToFile() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Color.nannyAccent)
                    .disabled(logger.entries.isEmpty)
            } content: {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if logger.entries.isEmpty {
                            Text("No entries yet. Trigger a notification to start logging.")
                                .font(.caption2).foregroundStyle(.tertiary).padding(10)
                        } else {
                            ForEach(logger.entries.reversed()) { LogEntryRow(entry: $0) }
                        }
                    }
                    .padding(6)
                }
                .frame(height: 260)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            // MARK: Edge-case tools
            CollapsibleSection(title: "Edge-case tools", systemImage: "hammer") {
                EmptyView()
            } content: {
                VStack(spacing: 0) {
                    toolRow(title: "Dump AX tree",
                            subtitle: "Logs the live Notification Center window tree for any banners on screen.") {
                        Button { repositioner.dumpBannerDiagnostics() } label: {
                            Label("Dump", systemImage: "list.bullet.indent")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!repositioner.isObserving)
                    }
                    Divider().padding(.leading, 14)
                    toolRow(title: "Back-to-back burst",
                            subtitle: "Fires several notifications in rapid succession to reproduce the rapid-message race.") {
                        Stepper("\(burstCount)", value: $burstCount, in: 2...8).fixedSize().controlSize(.small)
                        Button { repositioner.sendBurstTest(count: burstCount) } label: {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    Divider().padding(.leading, 14)
                    toolRow(title: "Edge-case notifications",
                            subtitle: "Send a tricky notification through the real path to test extraction, wrapping, and unicode. Renders custom only when custom mode is active for the sender.") {
                        Menu {
                            ForEach(TestNotification.scenarios) { scenario in
                                Button(scenario.label) { repositioner.sendEdgeCase(scenario) }
                            }
                        } label: {
                            Label("Send", systemImage: "ellipsis.bubble")
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .onAppear(perform: refreshDiagnostics)
    }

    private func refreshDiagnostics() {
        diagItems = Diagnostics.collect(settings: settings, repositioner: repositioner, launchAtLogin: launchAtLogin)
    }

    @ViewBuilder
    private func toolRow<Trailing: View>(title: String, subtitle: String,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

/// A titled card whose body collapses/expands. Header shows an icon + title, optional trailing
/// controls (only while expanded), and a rotating chevron.
private struct CollapsibleSection<Trailing: View, Content: View>: View {
    let title: String
    let systemImage: String
    var initiallyExpanded: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool

    init(title: String, systemImage: String, initiallyExpanded: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.initiallyExpanded = initiallyExpanded
        self.trailing = trailing
        self.content = content
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage).font(.caption).foregroundStyle(.secondary).frame(width: 14)
                        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded { trailing() }
            }
            if expanded { content() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
