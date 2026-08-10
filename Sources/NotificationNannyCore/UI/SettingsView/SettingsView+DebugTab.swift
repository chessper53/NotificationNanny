import SwiftUI
import AppKit

/// Diagnostics & developer tools: health checks, the activity log, and tools for reproducing /
/// inspecting notification edge cases. The single place to gather everything for a bug report.
struct DebugTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var repositioner: NotificationRepositioner
    @EnvironmentObject var launchAtLogin: LaunchAtLogin
    @ObservedObject private var logger = NannyLogger.shared

    @State private var diagCopied = false
    @State private var burstCount = 3
    @State private var pasteText = ""
    @State private var applyResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: One-tap report — everything a bug report needs, on the clipboard.
            VStack(alignment: .leading, spacing: 10) {
                Label("Diagnostics", systemImage: "stethoscope")
                    .font(.headline).foregroundStyle(.primary)
                Text("Copies your settings, system info, and recent activity. Paste it into your bug report.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    let report = Diagnostics.fullReport(
                        Diagnostics.collect(settings: settings, repositioner: repositioner, launchAtLogin: launchAtLogin))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    diagCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { diagCopied = false }
                } label: {
                    Label(diagCopied ? "Copied to clipboard" : "Copy Diagnostics",
                          systemImage: diagCopied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(diagCopied ? .green : Color.nannyAccent)
                .animation(.easeInOut(duration: 0.15), value: diagCopied)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            // MARK: Developer — repro a pasted report, inspect logs, drive edge cases.
            CollapsibleSection(title: "Developer", systemImage: "hammer") {
                EmptyView()
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    applyReportTool
                    activityLog
                    edgeCaseTools
                }
            }

            Spacer()
        }
    }

    // MARK: Apply a pasted diagnostics report

    private var applyReportTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apply a report")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text("Paste a diagnostics report to take over its settings (position, behavior toggles, auto-dismiss, scale) for local reproduction.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $pasteText)
                .font(.caption2.monospaced())
                .frame(height: 110)
                .padding(4)
                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
            HStack(spacing: 8) {
                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string) { pasteText = pasted }
                } label: { Label("Paste", systemImage: "clipboard") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {
                    let applied = Diagnostics.applyReport(pasteText, to: settings)
                    applyResult = applied.isEmpty
                        ? "Nothing recognized — paste a full diagnostics report."
                        : "Applied \(applied.count): " + applied.joined(separator: ", ")
                } label: { Label("Apply Settings", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(Color.nannyAccent)
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let applyResult {
                Text(applyResult)
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Activity log

    private var activityLog: some View {
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
    }

    // MARK: Edge-case tools

    private var edgeCaseTools: some View {
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
