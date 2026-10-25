# Investigation: a custom Notification Center panel

Can the open Notification Center panel be replaced the way the custom banner replaces a
banner? Yes. This is what was measured, what was built on it, and what is still open.
Everything below was measured on macOS 27.0 and 27.0.1, with a 5120×1440 main display
and the built-in 1710×1107 one.

## The banner trick, and why the panel is different

The custom banner leaves Notification Center in charge. We read the banner through
Accessibility, park its window off screen, draw our own, and pass clicks back to the real
one (`AXPress` to open it, its Close action to close it). Notification Center stays the
source of truth for what exists.

The panel can be treated the same way, with one exception that needed its own answer: a
click on any window of ours closes the real panel.

## Measurements

Tools: [`scripts/panel-probe.swift`](../scripts/panel-probe.swift) surveys the panel, and
[`scripts/panel-lab`](../scripts/panel-lab/run.sh) runs one experiment per question. Both
only ever act on notifications from the notify-lab apps, and the probe replaces the text
of anything else with its length.

| Question | Answer |
|---|---|
| Where does the panel live? | In the same fullscreen `AXSystemDialog` window as the banners. Its position can be set, its size can't. With nothing up and the panel closed, Notification Center has no window at all. |
| How soon can it be seen open? | `AXExpanded` on Notification Center's application element and the Edit Widgets button both appear about 225 ms after the clock press. `AXFocusedWindowChanged` and `AXLayoutChanged` arrive at the same moment, so no polling is needed. The rows sometimes arrive a few tens of milliseconds after `AXExpanded`. |
| Does it stay open off screen? | Yes. Parked at y = −9999 it stays open, and its rows still answer to their actions. |
| Can the window be parked before it opens? | No. Notification Center moves its window back to where it was when the panel opens. |
| Is there a flash? | Filmed with `screencapture`: without parking the panel shows for about 2.4 s; parked 13 ms after `AXExpanded`, not one frame of it was caught (recordings ran at 16 to 30 fps). |
| Can the window be faded instead? | No. `CGSSetWindowAlpha` on it reports success and changes nothing. |
| Is the whole list in the tree? | Yes. 36 rows were all there, 21 of them below the visible part. Scrolling it from outside does nothing (`AXScrollToVisible`, `AXScrollDownByPage`, the wheel), and nothing needs it. |
| Are rows stable? | `AXIdentifier` stays the same from banner to panel row and across the panel closing and opening. |
| What does a row offer? | `AXPress` (opens it, or expands a collapsed stack), Show Details, Close or Clear All, and the app's own actions such as Show and Reply. Title, subtitle and body are labelled children. No timestamp is exposed. |
| How is the list laid out? | Flat. Alerts still up come first. Then a "Notification Center" heading with its Clear All button, then the history. An expanded stack is a heading with the app's name, Show Less and Clear buttons, then one row each. |
| Is the tree in the order it is drawn? | No. The header of a stack expanded after others came first in the tree. The list has to be sorted by position. |
| Can it be opened or closed directly? | No. `AXExpanded` is not settable and the application element has no actions. The menu bar clock (in MenuBarAgent since 27.0, found by hit testing) toggles it. |
| What does a click on a window of ours do? | It closes the real panel, even for a non-activating panel. A scroll wheel over it does not. |
| Can that click be kept from it? | Yes. An event tap at the head of the session that takes the click out of the stream, and sends it to our window directly, leaves the real panel open, and our view still gets the click. |
| Does opening a notification close the panel? | Not while parked; it does when clicked in the real panel. |

## What was built

Behind the experimental setting "Custom Notification Center" (General, off by default):

- `NCPanelTakeover` sees the panel open from the AX events, parks the window at once and
  keeps it parked, reads the list in drawn order into `NCPanelSnapshot`, and passes our
  actions back by row identifier: open, close, expand, Show Less, Clear, Clear All. After
  opening a notification it closes the real panel through the clock, as Notification
  Center does itself.
- `PanelClickRouter` is the event tap. It runs only while our panel is on screen and only
  takes mouse events that start inside it. Clicks anywhere else go through, so a click
  outside still closes Notification Center's panel, and ours with it.
- `CustomNCPanel` draws the list: flat graphite and amber, following Light Mode, as tall
  as its content (the router takes every click inside the window, so it must not have an
  empty margin). It adds a filter by app, and a tint edge for apps whose exception group
  has a colour of their own.
- While it is open, custom banner overlays are put away, as Notification Center moves open
  alerts into its panel; the sweep after it closes brings them back.

Checked live with [`scripts/panel-lab/app.sh`](../scripts/panel-lab/app.sh), which runs a
debug build with only the Lab apps listed: opening, expanding a stack, Show Less, closing a
row, clearing a group, a notification arriving while open, scrolling, opening a
notification, and opening from the second display's clock. The real panel stayed parked
and open throughout, and settings were restored and checked after every run.

## Still open

- Widgets are not shown. They are drawn by their own processes and Accessibility doesn't
  describe them.
- Clear All on the history section was not pressed in a test: it would clear the real
  notifications on this Mac. Notification Center may ask for confirmation there.
- Keyboard: Escape and arrow keys are untested. Our panel never takes focus.
- App actions such as Reply are not offered yet; Reply needs a text field, which would
  need focus.
- No timestamps, since Notification Center doesn't expose any. The app could keep its own
  from when it first saw each banner.
- Hover only expands a long body if SwiftUI delivers hover to a window that is never key;
  not checked.
- Only measured on 27.0. A release without `AXExpanded` never takes over.
