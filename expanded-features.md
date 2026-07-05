# Expanded Features

## 1. Bluetooth Headphone Indicator

Shows a short closed-notch animation when Bluetooth headphones become the active audio output on macOS.

Details:
- Triggers when devices like AirPods or other Bluetooth headphones are selected as the current output device.
- Uses Bluetooth device matching to show a more accurate profile or icon when possible.
- Avoids showing the animation for every Bluetooth event and only reacts to active audio output changes.

## 2. Timer and Stopwatch Support

Adds a built-in timer and stopwatch inside the notch so users can start and manage time-based activities without opening another app.

Details:
- Lets users switch between timer and stopwatch modes from the Activities tab.
- Shows active time sessions directly in the notch, including when the notch is closed.
- When the closed clock activity is visible, hovering it opens the notch directly into the Activities space.
- Supports timer adjustments with `Option` + two-finger horizontal swipe, plus configurable sensitivity and direction settings.

## 3. Standalone Calendar Tab

Moves Calendar out of the music view and into its own dedicated tab.

Details:
- Uses a two-column layout with a complete month grid on the left and the selected day's events and reminders on the right.
- Supports discrete month navigation with `Option` + two-finger horizontal swipe without interfering with normal tab gestures.
- Preserves the selected day number between months, clamping it when the destination month is shorter.
- Uses red calendar controls while preserving each event's source-calendar color.

## 4. Hover-To-Open Live Activities

Makes the closed live activity surfaces act like shortcuts into the expanded notch views.

Details:
- Hovering the music live activity opens the notch into the Home space, where playback controls are available.
- Hovering the closed clock side activity opens the notch into the Activities space.
- This works with the existing notch hover behavior, so users can move from a compact live activity to its expanded view without clicking.

## 5. Multi-Space Navigation With Two-Finger Gestures

Adds support for moving between notch tabs while using multiple macOS Spaces, using two-finger horizontal swipe gestures when the notch is open.

Details:
- Allows navigation between Home, Calendar, Activities, and Shelf with horizontal trackpad gestures.
- Includes settings for gesture enablement, direction inversion, and sensitivity.
- Keeps gesture navigation separate from normal tab interactions so switching tabs feels more consistent across Spaces.

## 6. Optional Tinted Tab Icons

Adds a General setting for identifying the selected tab by color.

Details:
- Uses blue for Home and Shelf, red for Calendar, and orange for Activities.
- Applies color only to the selected tab icon; inactive icons remain gray.
- Keeps the existing white selected-icon appearance when the setting is disabled.
