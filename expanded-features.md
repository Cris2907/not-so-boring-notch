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
- Supports timer adjustments with `Option` + two-finger horizontal swipe, plus configurable sensitivity and direction settings.

## 3. Multi-Space Navigation With Two-Finger Gestures

Adds support for moving between notch tabs while using multiple macOS Spaces, using two-finger horizontal swipe gestures when the notch is open.

Details:
- Allows navigation between Home, Activities, and Shelf with horizontal trackpad gestures.
- Includes settings for gesture enablement, direction inversion, and sensitivity.
- Keeps gesture navigation separate from normal tab interactions so switching tabs feels more consistent across Spaces.
