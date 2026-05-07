import AppKit

@MainActor
final class HotkeyManager {
    private weak var settings: AppSettings?
    private var monitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.option, .command, .control, .shift]) == .option,
              let char = event.charactersIgnoringModifiers,
              let digit = char.first.flatMap({ Int(String($0)) }),
              (1...5).contains(digit) else { return }
        guard let settings, digit <= settings.presets.count else { return }
        settings.applyPreset(settings.presets[digit - 1])
    }
}
