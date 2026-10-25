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
| Are rows stable? | `AXIdentifier` stays the same from banner to panel row and across the panel closing and opening. Each notification in a stack keeps the identifier it had as a banner (6 of 6), and a collapsed stack carries its newest notification's. |
| What does a row offer? | `AXPress` (opens it, or expands a collapsed stack), Show Details, Close or Clear All, and the app's own actions such as Show and Reply. Title, subtitle and body are labelled children. No timestamp is exposed. |
| How is the list laid out? | Flat. Alerts still up come first. Then a "Notification Center" heading with its Clear All button, then the history. An expanded stack is a heading with the app's name, Show Less and Clear buttons, then one row each. |
| Is the tree in the order it is drawn? | No. The header of a stack expanded after others came first in the tree. The list has to be sorted by position. |
| Can it be opened or closed directly? | No. `AXExpanded` is not settable and the application element has no actions. The menu bar clock (in MenuBarAgent since 27.0, found by hit testing) toggles it. |
| What does a click on a window of ours do? | It closes the real panel, even for a non-activating panel. A scroll wheel over it does not. |
| Can that click be kept from it? | Yes. An event tap at the head of the session that takes the click out of the stream, and sends it to our window directly, leaves the real panel open, and our view still gets the click. |
| Does opening a notification close the panel? | Not while parked; it does when clicked in the real panel. |
| Does Clear All on the history ask first? | No. One press cleared it, and the panel stayed open. |

## Widgets

Widgets and notifications are drawn by the same process. Each desktop widget is a window
of Notification Center's own (`AXUnknown`, on the desktop layer), and a widget in the
panel sits in the panel's scroll area, in an `AXOpaqueProviderGroup` above the
notifications. Either way a widget's element has an identifier
`widget-local:<app>:<kind>:<container>`, for example
`widget-local:com.apple.weather:com.apple.weather.widget:com.apple.weather`.

| Question | Answer |
|---|---|
| Can a widget be read? | Its text, yes: the Weather widget describes itself as place, temperature, conditions, warning, high and low, then one element per hour. Not its look. |
| Can it be clicked through Accessibility? | No. Its parts only offer `AXScrollToVisible`; there is no `AXPress`. |
| Can it be captured as a picture? | Not while parked: a window wholly off screen isn't drawn, and `screencapture -l` fails. On screen, yes, even covered by a window of ours above it (level 25 over Notification Center's 21): the real Weather widget came out pixel for pixel. That needs Screen Recording. |
| A trap for anything that moves windows | With the panel closed, a desktop widget can be Notification Center's only window. A lab cleanup that took the widest window for the panel's moved a desktop widget to (0,0). Only the `AXSystemDialog` window is the panel's. |

Shown as pictures of the real ones, behind the "Show widgets" setting (off by default,
needs Screen Recording; off, widgets are left out). Measured in the app:

| Question | Answer |
|---|---|
| How does the real panel get under ours without showing? | It is parked as usual when it opens. Once ours is up, an opaque cover goes where the real panel will land, between the two (level 22), and then the real panel moves there. |
| Does that, or capturing, close the real panel? | No. Held under a cover for 6 s it stayed open with no capture, with `screencapture` and with ScreenCaptureKit every 2 s. One run that closed was a click by the user. |
| How long does a capture take? | About 150 ms with ScreenCaptureKit, 500 ms for the first. |
| What went wrong first? | The panel slides in when it opens, and a widget's frame read at the start of a capture no longer matched by its end: the picture showed the wrong part. A capture now counts only if the widgets didn't move meanwhile, and tries again shortly otherwise. |
| Can a click reach the real widget? | Sent to Notification Center with `postToPid`, no. As a real click at the real widget's place, with our panel and the click router letting it through for that one click, yes: Weather opened, and Notification Center closed its panel as it does after a widget click. The pointer jumps there and back. |

## The app's own buttons: Reply, Archive, Snooze

A notification can carry buttons of its app's own. macOS shows them when the banner is
hovered and expanded, and on alerts. Notification Center lists them as custom actions of
the notification's element, beside its own (Close, Show Details, Clear All). Measured on
27.0 with a Lab app posting Reply (with a text field), Archive and Snooze, and logging what
reached it (`scripts/notify-lab/notifier.swift`, `responses.log`):

| Question | Answer |
|---|---|
| Does performing one reach the app? | Yes. Archive through Accessibility arrived as `action=archive` for the right notification, on a banner and on a parked panel row. |
| What does Reply do? | Notification Center expands the notification and shows its own text field (`AXTextArea`, writable), the app's placeholder, and a Send button; Reply is replaced by Send in the actions. Performing Reply reports an error code while doing all of that. |
| Can the reply be filled and sent? | Writing the field's value and pressing Send arrived as `action=reply text=…`. |
| Can a person type into it, with the real one off screen? | Yes. Given the focus through Accessibility, Notification Center takes the keyboard while the frontmost app stays frontmost, and real keystrokes land in the field, on a parked banner and in the parked panel, which stays open. The lab only types once the system says that field has the focus. |
| Hover | SwiftUI's `onHover` and AppKit tracking areas, even always-active ones, never reported in a window of an app that isn't active (`hover-test`); NotificationNanny never is. Reading the pointer position does work. |

So both the custom banner and the custom panel can mirror the real notification: our
buttons perform the app's actions on the real one, and a reply is typed into Notification
Center's own field, which has the focus, while ours shows what it holds. Send needs no name:
it is the action that appears when the reply opens. Built, not yet checked live.

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
- Times on each row, behind their own setting: Notification Center draws them but doesn't
  expose them, so `NotificationTimes` notes when each banner first shows and keeps it by
  identifier. Rows that were already listed when the app first saw them (they came in
  while it wasn't running, or alerts already up at launch) get no time rather than a
  wrong one.
- While it is open, custom banner overlays are put away, as Notification Center moves open
  alerts into its panel; the sweep after it closes brings them back.

Checked live with [`scripts/panel-lab/app.sh`](../scripts/panel-lab/app.sh), which runs a
debug build with only the Lab apps listed: opening, expanding a stack, Show Less, closing a
row, clearing a group, a notification arriving while open, scrolling, opening a
notification, and opening from the second display's clock. The real panel stayed parked
and open throughout, and settings were restored and checked after every run.

## Still open

- Widgets: only one widget, Weather, tested. The pointer visibly jumps for a widget click.
- Times are unit tested but not yet seen live: the screen locked during that run.
- Keyboard: Escape and arrow keys are untested. Our panel never takes focus.
- App actions such as Reply are not offered yet; Reply needs a text field, which would
  need focus.
- Hover only expands a long body if SwiftUI delivers hover to a window that is never key;
  not checked.
- Only measured on 27.0. A release without `AXExpanded` never takes over.
