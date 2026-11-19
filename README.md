# StudyHourglass

A minimalist, numbers-only floating countdown timer pill for macOS, built in native Swift and SwiftUI.

StudyHourglass puts a compact, translucent timer on top of your desktop and gets out of the way while you study. When the session ends, it interrupts you clearly: a centered **Time's Up!** card, a chime that keeps looping, and a flashing pill, all of which continue until you respond.

---

## Key Features

- **Always-on-top countdown pill.** A dark translucent pill with bold monospaced digits floats above every app, Space and full-screen window. It shows `MM:SS`, or `HH:MM:SS` for sessions of an hour or longer.
- **Free drag positioning.** Drag the pill anywhere on screen. Its position is saved and restored on the next launch. **Dock Right** in the menu bar moves it back to the right edge.
- **Scaling from 0.6× to 2.5×.** Resize from the corner grip on the pill (shown on hover), with a trackpad pinch or ⌘-scroll, or with the menu bar slider and presets. The aspect ratio stays fixed, the text stays sharp at every size, and the chosen size is saved.
- **Hover controls.** Hovering over the pill shows a small control bar underneath it:
  - Play / Pause
  - Reset
  - Duration menu with presets (1 min, 25 min, 30 min, 1 hr) and **Custom…** input, which accepts either total minutes (`90`) or `H:MM` (`1:30`)
- **"Time's Up!" alert that interrupts you.** At `00:00`:
  - A centered alert card appears above all other windows, on the screen your pointer is on. It shows the length of the session that finished and has **Dismiss** and **Restart** buttons.
  - A looping chime (macOS **Glass**, with **Hero** as a fallback) plays every 2 seconds until you dismiss, restart or reset.
  - The floating pill flashes red and amber with a pulsing glow.
  - A macOS notification banner is also posted, so the session appears in Notification Center.
- **Menu bar app.** The app lives in the menu bar, has no Dock icon, and shows the live countdown next to its menu bar icon.

---

## Keyboard Shortcuts & Controls

### Time's Up! card

| Key | Action |
| --- | --- |
| `Return` | Dismiss the alarm |
| `Esc` | Dismiss the alarm |
| `R` | Restart the same session from the beginning |

### Floating pill

| Action | How |
| --- | --- |
| Move | Drag the pill |
| Resize | Drag the bottom-right corner grip, pinch on a trackpad, or ⌘-scroll |
| Show controls | Hover over the pill |

### Menu bar popover

| Option | Description |
| --- | --- |
| Start / Pause, Reset | Control the current session |
| Dismiss Alarm | Shown while the alarm is going |
| Duration presets / custom | Same presets as the pill; the text field accepts `90` or `1:30` |
| **Alarm sound** toggle | Turns the looping chime on or off. Turning it off silences a running alarm immediately |
| **Test Sound** | Plays a single chime |
| **Size presets** | Compact (0.8×), Normal (1.0×), Large (1.6×) |
| Size slider | Any size from 0.6× to 2.5× |
| Show / Hide Widget, Dock Right, Quit | Window management |

---

## Build & Installation

### Requirements

- macOS 26.6 or later
- Xcode 26 or later

### Option 1: Xcode

1. Open `StudyHourglass.xcodeproj` in Xcode.
2. Select the **StudyHourglass** scheme and **My Mac** as the destination.
3. Press **⌘R** to build and run, or use **Product ▸ Archive** for a Release build.

### Option 2: Command line (`xcodebuild`)

```bash
# Build. If `xcode-select` points at the Command Line Tools,
# set DEVELOPER_DIR to the full Xcode instead.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project StudyHourglass.xcodeproj \
             -scheme StudyHourglass \
             -configuration Release \
             -destination 'platform=macOS' \
             -derivedDataPath build \
             build
```

### Install to /Applications

```bash
# Quit any running copy, then replace the installed app
pkill -x StudyHourglass 2>/dev/null
rm -rf /Applications/StudyHourglass.app
ditto build/Build/Products/Release/StudyHourglass.app /Applications/StudyHourglass.app
open /Applications/StudyHourglass.app
```

If you built from Xcode without `-derivedDataPath`, the app is in
`~/Library/Developer/Xcode/DerivedData/StudyHourglass-*/Build/Products/<Configuration>/StudyHourglass.app`.

On first launch, macOS asks for permission to show notifications. Allow it to get the "Time's Up!" banner in addition to the alert card.

---

## Project Structure

| File | Purpose |
| --- | --- |
| `MyApp.swift` | App entry point, menu bar extra and popover, app delegate |
| `ContentView.swift` | Floating timer pill, hover controls, Time's Up! card view |
| `FloatingPanel.swift` | Floating window, drag and resize handling, size settings (`WidgetLayout`), alarm window |
| `TimerModel.swift` | Countdown state, time formatting and parsing, alarm state |
| `ChimePlayer.swift` | Looping alarm sound and notification banner |
| `HourglassView.swift` | Previous animated hourglass renderer (not used by the current pill UI) |
