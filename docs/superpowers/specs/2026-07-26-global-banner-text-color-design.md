# Global Banner Text Color Design

## Goal

Let users choose one global text color for custom NotificationNanny banners.

## Scope

Add a single global text-color override. It applies to the custom banner renderer
only; native macOS notifications keep their system-controlled text colors. There
are no per-app or per-group overrides.

## Settings model

Store the override as an optional `BannerTint` in `AppSettings`, backed by RGB
values and a presence flag in `UserDefaults`. `nil` means the existing default:
white text. A non-nil override activates the custom renderer, because native
banners cannot honor the setting. Resetting the setting clears the override and
returns the effective text color to white.

Follow the existing background-color behavior: the setting is global runtime
configuration and is not added to presets or backup/export data.

## Rendering

Resolve the effective text color once when the overlay is created and pass it
to `CustomBannerView`.

- Notification title: full selected color.
- Body: selected color at 85% opacity.
- App name and timestamp: selected color at lower opacity for hierarchy.
- Close control and icon treatment remain unchanged.

The banner-animation preview receives the same color so the settings UI
accurately represents the rendered overlay.

## Settings UI

Add a `Text Color` card beside the existing `Background Color` card in the
Banner settings tab. It contains a standard SwiftUI color picker and a Reset
button. The status text says `Default — white` when no override exists and
`Custom text color active — custom renderer on` otherwise.

## Validation

Add unit tests that verify the default is white/no override, a custom RGB value
persists across a new `AppSettings` instance, reset clears the override, and a
custom text color activates the custom-banner decision. Build the app and send
a test notification to visually confirm the picker affects title, body, and
metadata with the intended opacity hierarchy.
