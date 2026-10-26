# NotificationNanny Style Guide

How the Settings window looks and behaves, and the pieces it is built from. Read this
before adding or changing anything in `Sources/NotificationNannyCore/UI/SettingsView/`.

The pieces live in two files:

- [SettingsComponents.swift](../Sources/NotificationNannyCore/UI/SettingsView/SettingsComponents.swift): cards, rows, chips, swatches, menus, the switch and button styles.
- [GroupComponents.swift](../Sources/NotificationNannyCore/UI/SettingsView/GroupComponents.swift): the row of groups and the app picker, shared by every tab that has groups.

Colours live in [NannyColors.swift](../Sources/NotificationNannyCore/UI/NannyColors.swift).
If what you need isn't there, add it there, not inline in a tab.

## Principles

1. **Graphite and amber, flat.** Graphite surfaces, amber for what is chosen or can be
   acted on. No gradients, glows or decorative fills. The only gradients left are the
   dark mode screen previews, which predate this guide.
2. **macOS first.** Every setting starts as macOS has it, and the UI says so ("As
   macOS", "Default"). Anything macOS doesn't have starts off.
3. **Saved settings never change meaning.** People use this app. A new field is
   optional and its missing value means the old behaviour, with a test that loads
   settings saved without it. A UI change never rewrites a saved value the user didn't
   touch; showing a screen must not save anything.
4. **One way to do each thing.** If two tabs need the same control, it is one
   component. Copying a view into a second tab is how the card colour drifted before.
5. **Both appearances, every time.** Check Light and Dark before calling a change done.

## Layout

| What | Value |
| --- | --- |
| Tab content width | at most 600 pt, centred (`SettingsView.contentMaxWidth`) |
| Smallest window content | 620 × 412 pt |
| Tab padding | 16 pt |
| Space between cards | 14 pt |
| Card padding, space inside | 12 pt, 10 pt |
| Row in a list of rows | 14 pt across, 10 pt down (`.settingsListRow()`) |
| Corner radius | card 10, chip 8, small pill 6, preview well 10 |
| Swatch | 22 pt circle |

Previews that draw a screen size themselves to the card's measured width
(`PositionCard` does this). Never give a preview a fixed width: the window can be
narrow, and the card's padding takes room.

## Type

| Role | Style |
| --- | --- |
| Tab intro, at the top of a tab | `.callout`, `Color.nannyMuted(0.55)` |
| Card title | `.caption.weight(.medium)`, `.secondary` (`SettingsCardHeader`) |
| Section title over a list of rows (General) | `.caption2.weight(.semibold)`, uppercase, `.tertiary`, kerning 0.5 |
| Row label | `.callout` |
| Row detail under a label | `.caption`, `.secondary` |
| Note under a setting | `.caption2`, `Color.nannyNote` (`SettingsNote`) |
| Numbers that change (percent, size, offsets) | `.caption2.monospacedDigit()` |

## Colour tokens

| Token | Use for |
| --- | --- |
| `nannyAccent` | Small amber: text buttons (Reset, Replay, Play), icons that mark a choice, the plus on "New group". Deeper on light so it stays readable. |
| `nannyProminent` | Large fills: the selected chip, the prominent button. Amber on dark, graphite on light, where a large amber area turns brown under text. |
| `nannySwitchOn` | A switch that is on. Amber in both appearances: it carries no text. |
| `nannyCard` | Card background. White on light, a white lift on dark. |
| `nannySegment` | The chosen segment of a segmented control. |
| `nannyNote` | Notes and other small print. |
| `nannyRaised(x)` | Unselected chips, pills and tracks inside a card. |
| `nannyInset(x)` | Recessed wells: the animation preview, the app list. |
| `nannyWash(x)` | Behind a selected row in a list. |
| `nannyStrong` | The ring around a chosen swatch, strong text on a raised pill. |
| `ScreenPreview.*` | The device previews: wallpaper, menu bar, dock, device shell. |

A colour that only matters in one appearance gets a token with its own light value
(`nannyAdaptive(light:dark:)`), so the other appearance stays exactly as it was.

## Components

### Structure

- **`SettingsCard`**: every setting sits in one. Title on top, the control, a note at
  the bottom.
- **`SettingsCardHeader`**: the card's title, with one action on its right if the
  card has one (Reset, Replay, Play, a display menu).
- **`SettingsNote`**: what the setting does right now, in one or two plain sentences.
  It changes with the setting ("Default. Follows system appearance", "Tint active").
- **`.settingsCardBackground()` and `.settingsListRow()`**: for a list of rows that
  isn't a `SettingsCard`, as on General, Presets and Help.

### Choices

| Choice | Component |
| --- | --- |
| On or off | `SettingsToggleRow`, or `Toggle` with `.toggleStyle(.nannySwitch)` |
| Two or three short options | `NannySegmentedPicker` (`compact: true` beside a label) |
| One of a longer list | `NannyMenuPicker` |
| A display | `DisplayPicker` |
| One of many, with icons | `ChoiceChip` in a grid (`AnimationChipGrid` for animations) |
| A colour | `ColorSwatchRow` |
| A size | `SettingsScaleSlider` |
| A place on screen | `PositionCard` |
| Follow another setting | `FollowChip` ("Same as banners", "Same as All apps") |

Never use the system's segmented control, `.pickerStyle(.menu)`, `.toggleStyle(.switch)`
or `.buttonStyle(.borderedProminent)` in Settings. They stretch across the row, or turn
grey whenever the window isn't focused, which for a Settings window left open beside
other apps is most of the time.

### "Default" and "Same as"

Every setting with a macOS default shows that default as its first choice, and it is
the one chosen while nothing of the user's own is set:

- Colours: `DefaultColorSwatch`, a hollow circle struck through. The custom colour
  well is grey while it is chosen, so a colour that only would apply never looks
  picked.
- Chips: a "Default" chip, first in the grid, with an icon for what the default is:
  the animation's own, a bell for the app's own sound. The struck through ring means
  "none", so it is only for a default that really is none, like no tint.
- Settings that can follow another one start with `FollowChip`, before the default.
  For a group, "Same as All apps" is the group having no value of its own, as it is
  stored (`nil`). Picking it clears the value.

Choosing the default is how a setting is reset. Don't add a separate Clear or Reset
next to a choice that already has a default option. Reset stays for sliders, where
there is no option to click.

### Buttons

- **`NannyProminentButtonStyle`** (`.buttonStyle(.nannyProminent)`): one per tab, full
  width, at the bottom, for the tab's one real action: Send Test Notification, Open
  Notification Center. Banners at the top of the window (Grant Access, Update Now) use
  it small.
- **`SettingsTextButton`**: Reset and similar, in a card's header.
- **`CardActionButton`**: an action with an icon in a card's header: Replay, Play,
  Choose File, Open Notification Settings.
- An action that belongs to one card goes in that card's header, not below the card,
  and never among the choices as if it were one of them.

### Chips

`ChoiceChip` takes an icon when the icons tell the choices apart (each animation has
its own). When every chip would get the same icon, as with sounds, leave it out: the
names say it.

### Groups

A tab whose settings can differ for some apps (Banner with exception groups, Sounds with
sound groups) is laid out the same way:

1. `GroupScopeBar` on top: "All apps", one chip per group, then a named button,
   "New exception group" or "New sound group". Never a bare plus. While there are no
   groups, a note under the bar says what a group is for.
2. All apps shows the tab's cards for everyone.
3. A group shows `GroupAppPicker` first, then where its apps go if that applies, then
   only the cards a group can change, each starting on "Same as All apps". Cards a
   group can't change are hidden, not greyed out.

## Words

- Plain sentences. Say what happens, not what the control is.
- No dashes as punctuation in UI text or docs. They read as machine written; use a
  full stop, a comma or a colon.
- Name groups by kind: "exception group", "sound group".
- Every string goes through `LocalizedText` or `loc.string`, keyed by its English
  text, with a translation in all five `Resources/*.lproj/Localizable.strings` (en,
  de, fr, es, it). Language names in the language picker stay in their own language.
- Help tooltips (`.help`) on anything that is only an icon.

## Checking a change

1. `make test` passes (setup in [ARCHITECTURE.md](ARCHITECTURE.md), section 7), and
   `./scripts/dev.sh` shows the change working in the real window.
2. Render every tab in Light and Dark and look at them:

   ```sh
   NN_SNAPSHOT_DIR="$PWD/build/snapshots-check" scripts/test.sh --filter SettingsSnapshot
   ```

   Run it on its own: the demo data it registers trips other tests running beside it.
   A new tab goes in the list in `SettingsSnapshotTests`.
3. Look at the window unfocused too (click another app): nothing should turn grey.
4. If a saved setting is involved, add a test that loads settings saved before the
   change and checks they behave as before.
