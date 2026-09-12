import SwiftUI

struct PresetsTabView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var loc = LocalizationManager.shared

    private enum PresetMode: Equatable { case idle, renaming(UUID) }

    @State private var presetMode: PresetMode = .idle
    @State private var pendingName = ""
    @State private var appliedPresetID: UUID? = nil
    @State private var pendingApply: Preset? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Save and switch between named configurations. Presets capture your full setup including per-app rules.")
                .font(.callout)
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)

            LocalizedText("Presets").font(.caption.weight(.medium)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                if settings.presets.isEmpty {
                    LocalizedText("No presets yet.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    ForEach(Array(settings.presets.enumerated()), id: \.element.id) { index, preset in
                        presetRow(preset, index: index)
                        if index < settings.presets.count - 1 || settings.presets.count < 5 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }

                if settings.presets.count < 5 {
                    if !settings.presets.isEmpty { Divider().padding(.leading, 14) }
                    HStack(spacing: 6) {
                        TextField(loc.string("Name"), text: $pendingName)
                            .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption)
                            .onSubmit { commitPreset() }
                        Button(loc.string("Save"), action: commitPreset)
                            .buttonStyle(.borderedProminent).controlSize(.mini)
                            .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(loc.string("Cancel")) { pendingName = "" }.buttonStyle(.borderless).controlSize(.mini)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    Divider().padding(.leading, 14)
                    LocalizedText("5 preset limit reached")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .confirmationDialog(
            loc.string("Replace your current exception groups?"),
            isPresented: Binding(get: { pendingApply != nil }, set: { if !$0 { pendingApply = nil } }),
            titleVisibility: .visible
        ) {
            Button(loc.string("Apply Preset"), role: .destructive) {
                guard let preset = pendingApply else { return }
                applyPreset(preset)
                pendingApply = nil
            }
            Button(loc.string("Cancel"), role: .cancel) { pendingApply = nil }
        } message: {
            Text("“\(pendingApply?.name ?? "")” was saved with a different set of exception groups. Applying it will replace your current groups — this can't be undone.")
        }
    }

    private func applyPreset(_ preset: Preset) {
        settings.applyPreset(preset)
        appliedPresetID = preset.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { appliedPresetID = nil }
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset, index: Int) -> some View {
        if presetMode == .renaming(preset.id) {
            HStack(spacing: 6) {
                TextField("", text: $pendingName)
                    .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption)
                    .onSubmit { commitRename(preset) }
                Button(loc.string("Done")) { commitRename(preset) }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                    .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { cancelRename() } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        } else {
            HStack(spacing: 4) {
                Button {
                    if !settings.appGroups.isEmpty, settings.appGroups != preset.appGroups {
                        pendingApply = preset
                    } else {
                        applyPreset(preset)
                    }
                } label: {
                    Label(
                        appliedPresetID == preset.id ? "Applied!" : preset.name,
                        systemImage: appliedPresetID == preset.id ? "checkmark" : ""
                    )
                    .animation(.easeInOut(duration: 0.15), value: appliedPresetID)
                }
                .buttonStyle(.borderless).font(.callout)
                .foregroundStyle(appliedPresetID == preset.id ? Color.green : Color.primary)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.15), value: appliedPresetID)

                Spacer()
                Button { movePreset(at: index, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(index == 0)
                Button { movePreset(at: index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .disabled(index == settings.presets.count - 1)
                Button { beginRename(preset) } label: { Image(systemName: "pencil").font(.caption2) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                Button { settings.deletePreset(preset) } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func movePreset(at index: Int, by offset: Int) {
        let dest = index + offset
        guard dest >= 0, dest < settings.presets.count else { return }
        var updated = settings.presets; updated.swapAt(index, dest); settings.presets = updated
    }

    private func beginRename(_ preset: Preset) { presetMode = .renaming(preset.id); pendingName = preset.name }

    private func commitRename(_ preset: Preset) {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = settings.presets.firstIndex(where: { $0.id == preset.id }) else { cancelRename(); return }
        var updated = settings.presets; updated[i].name = trimmed; settings.presets = updated
        presetMode = .idle; pendingName = ""
    }

    private func cancelRename() { presetMode = .idle; pendingName = "" }

    private func commitPreset() {
        let name = pendingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        settings.saveCurrentAsPreset(name: name)
        pendingName = ""
    }
}
