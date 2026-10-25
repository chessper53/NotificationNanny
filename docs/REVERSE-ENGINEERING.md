# Reverse engineering Notification Center: progress

Where NotificationNanny stands in taking apart macOS's notifications and putting its own in
their place: the principle, what is done and how well it matches, what was learned, the
tools, and what is still open. Measured on macOS 27.0 and 27.0.1, with a 5120×1440 main
display and the built-in 1710×1107 one. The details behind each part are in
[INVESTIGATION-nc-panel.md](INVESTIGATION-nc-panel.md) and
[INVESTIGATION-relaunch-and-26.x.md](INVESTIGATION-relaunch-and-26.x.md); how the code fits
together is in [ARCHITECTURE.md](ARCHITECTURE.md).

## The principle

Notification Center keeps owning every notification. NotificationNanny reads it through
Accessibility, hides the real thing by moving its window off screen, draws its own in its
place, and hands every click, button and reply back to the real one. Nothing is
reimplemented that Notification Center already does; ours is a view of it, which is why it
keeps working with every app and every notification.

## Status

| Part | State | How close to macOS |
|---|---|---|
| Moving banners | Done, shipped | Native banners, moved |
| Custom banner, collapsed | Done, shipped | 2.98 levels off in Dark Mode, 3.28 in Light, over eight backgrounds (banner-lab) |
| Custom banner, hovered, details shown, reply open | Done | Same places to the point; reply field within 3 levels |
| App buttons and inline replies (banner and panel) | Done, tested with Lab apps | Reaches the app exactly as the system's button does |
| Custom Notification Center | Done, experimental | 3 to 7 levels off over the whole panel |
| Arrival times | Done, optional | Not in macOS; noted by NotificationNanny |
| Widgets in the custom Notification Center | Done, optional | Pictures of the real ones; a click reaches the real widget |
| Size, position (left, middle, right, lower), screen, colours, animation of the panel | Done | macOS by default |

## What was learned

### Where things are

- Since macOS 26 every banner, and the open Notification Center panel, live in one
  fullscreen `AXSystemDialog` window of `com.apple.notificationcenterui`. The window can be
  moved; nothing inside it can. A banner is never a new window, so `AXLayoutChanged` is the
  only sign one arrived.
- Banners and panel rows share subroles (`AXNotificationCenterBanner`, `…Alert`, `…Stack`)
  and carry an `AXIdentifier` that stays the same from banner to panel row and across the
  panel closing and opening, stacks included.
- The panel's list (`AXNotificationListItems`) holds every row, not just those in view, but
  not in the order it is drawn: it has to be sorted by position.
- `AXExpanded` on the application element says whether the panel is open. It can't be set;
  only the menu bar clock (in MenuBarAgent since 27.0) opens it.
- Each desktop widget is a Notification Center window of its own, and can be its only one:
  only the `AXSystemDialog` window may ever be moved.

### Hiding and showing

- Parked off screen the panel stays open and every action still works. Notification Center
  moves its window back when the panel opens, so it can only be parked after; done as soon
  as `AXExpanded` turns true, not one frame of the real panel was filmed.
- A window wholly off screen isn't drawn. To picture widgets, the real panel goes under
  ours behind an opaque cover instead, where it is drawn but not seen.
- A click on any window of ours closes the real panel. An event tap that takes the clicks
  starting in ours and hands them to our window directly keeps it open.

### Acting on notifications

- An app's buttons (Reply, Archive, Snooze…) are custom actions of the notification's
  element, next to Notification Center's own. Performing one reaches the app as a click
  does (a Lab app logs `action=archive`).
- Reply opens Notification Center's own text field and replaces Reply with the app's send
  action. Given the focus, the field takes real keystrokes while the frontmost app stays
  frontmost, banner or parked panel alike.
- A widget offers nothing to Accessibility; a real click on the real widget, with ours
  letting it through, opens its app.

### How it looks

- The system's glass in Light Mode lets more of the background through than ours did and
  brightens it by a constant, which a white wash can't give; plus-lighter can.
- Banners shine all round their edge. Panel rows are lit at the top and bottom, with a
  dark line along their sides.
- Notification Center darkens what is behind its list: the column by 12%, fading in at the
  top, behind the rows by 10% more, in both appearances. That is why its rows look darker
  than banners.
- Hovered, a banner shows its close button, a chevron and an Options menu; with details, a
  more menu, the chevron turned down, and the buttons as plain rows under hairlines.
- In Dark Mode the real panel's brightness moves by about ten levels between runs with the
  same backdrop; Light Mode is steady.

### Things that misled us

- `onHover` and AppKit tracking areas report nothing in a window of an app that isn't
  active, which NotificationNanny never is: hover reads the pointer position instead.
- Synthetic pointer moves sometimes don't count as entering a banner; a lab tool that exits
  right after posting an event can lose it.
- A capture of the screen behind a transparent window shows what the user has open; on
  screen captures go over a gray backdrop of our own.
- A plain window showing up closes Notification Center's panel; a non-activating panel
  doesn't.

## Tools

| Tool | For |
|---|---|
| `scripts/ax-probe.swift` | Notification Center's tree and whether its window can be moved |
| `scripts/banner-lab/run.sh` | The custom banner against the real one, pixel by pixel, both appearances |
| `banner-lab` `real-states`, `prod-states`, `states_sheet.py` | Every state of a banner with buttons, real and ours side by side |
| `scripts/banner-lab/tune.py` | Tries look values against the real banner |
| `scripts/panel-probe.swift` | A survey of the open panel |
| `scripts/panel-lab/run.sh` and `lab.swift` | One experiment per question: identifiers, flash, the event tap, widgets, actions, replies, hover |
| `scripts/panel-lab/app.sh` | Drives a debug build step by step, settings restored and checked |
| `scripts/panel-lab/compare.sh` | The real panel and ours side by side, both appearances |
| `scripts/notify-lab` | Lab apps that post notifications, with buttons, and log what reaches them |

Rules the tools keep: only Lab notifications are ever acted on, other text is replaced by
its length, captures are of Lab rows or over our own backdrop, every setting touched is
restored and checked, and a new build's permissions are reset before it is launched.

## Open

- Only the Lab apps' buttons were tried, not a real app's reply.
- The more menu (⋯) of a banner with its details shown is drawn but does nothing yet.
- Widgets: one tested; the pointer visibly jumps for a click on one.
- Keyboard: Escape and arrow keys untested in the panel.
- Only measured on 27.0. Homebrew's Python 3.15 lacks numpy, so banner-lab scores with 3.14.
