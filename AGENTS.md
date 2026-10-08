# Conga

A macOS menu bar app that runs a shell command on a four-finger horizontal trackpad swipe.
Swipe left runs one command, swipe right another (defaults switch AeroSpace workspaces).
With natural scroll, the default, moving the fingers left is a swipe right.
While the fingers are down, an arrow in a glass box tracks progress; releasing past the
trigger distance runs the command, and swiping back before releasing cancels.
Swiping four fingers up fades in a row of squares in the same place, one per numbered AeroSpace
workspace that has windows, each showing the workspace number under previews of its windows.
It runs nothing and goes away when the fingers lift.

## Commands

```sh
swift build            # debug build
scripts/test.sh        # unit tests (extra args are passed to `swift test`)
scripts/bundle.sh      # release build wrapped in build/Conga.app, ad-hoc signed
open build/Conga.app
build/Conga.app/Contents/MacOS/Conga --preview-indicator 0.6   # hold the HUD at 60%; negative = left swipe
build/Conga.app/Contents/MacOS/Conga --preview-workspaces 1     # hold the workspace overlay fully shown
```

Use `scripts/test.sh` rather than bare `swift test`: the machine this was built on has only
the Command Line Tools (no Xcode), where SwiftPM does not find the Swift Testing macro plugin
by itself. For the same reason there is no Xcode project and no XCTest; tests use Swift Testing.

CI (`.github/workflows/test.yml`) runs `scripts/test.sh` on a `macos-26` runner for pushes to
`main` and for pull requests.

## Layout

- `Sources/CongaCore` — all logic, no AppKit. Everything here is unit tested.
  - `GestureRecognizer` — touch frames → `.progress` / `.peek` / `.fired` / `.cancelled`.
  - `GestureDispatcher` — one recognizer per trackpad; runs commands, emits indicator updates.
  - `IndicatorModel` — progress → opacity and arrow offset.
  - `Settings`, `SettingsStore` — values, clamping, `UserDefaults` persistence.
  - `ShellCommandRunner` — `/bin/sh -c`, fire and forget, or `output(of:)` to read stdout.
  - `WorkspaceOverview` — `aerospace` JSON → workspaces and their windows, and the overlay's
    geometry.
- `Sources/Conga` — the AppKit/SwiftUI shell: status item, settings window, the two HUD panels
  (`IndicatorWindow`, `WorkspaceOverlayWindow`, sharing `HUDStyle`), `WindowPreviews`, and
  `MultitouchMonitor`. Keep it thin; it has no tests.
- `Sources/CMultitouch` — C declarations for the private framework. No code.
- `Tests/CongaCoreTests` — tests for `CongaCore`.

New behaviour goes in `CongaCore` with tests; the app target should only wire things together.

## Things that are not obvious

- **Private API.** Touches come from `MultitouchSupport.framework`, because public APIs do not
  deliver four-finger touches to a background app. It needs no permissions, but the app cannot
  be sandboxed, and the `MTTouch` struct layout in `CMultitouch.h` is reverse-engineered and
  could change with a macOS release. If gestures stop working after an OS update, look there
  first. Trackpads connected after launch are not picked up until the app restarts or the Mac wakes.
- **Coordinates are normalised.** Touch positions are 0...1 across the trackpad, so the
  thresholds in `Settings` are fractions of trackpad width, and the settings UI shows percent.
- **Fire on release position, not peak.** The recognizer decides using the displacement at
  the moment fingers lift. That is what makes "swipe out, swipe back, release" cancel. After a
  gesture ends it ignores input until every finger has lifted.
- **Natural scroll.** `Settings.naturalScroll` (on by default) makes fingers moving left a
  swipe right, and the reverse. The recognizer always reports where the fingers went;
  `GestureDispatcher` turns that into the swipe, so the arrow and the command flip together
  and "Swipe left" / "Swipe right" in the settings name the swipe, not the finger movement.
- **One direction per touch.** The direction is fixed once the swipe passes the indicator
  start distance. Swiping back past the starting point only undoes the swipe; it never starts
  one in the opposite direction until the fingers lift and touch again. The starting point
  follows the fingers while they are behind it, so swiping in the original direction again
  starts from where they turned around.
- **Up is a direction, down is not.** A swipe up locks the same way and is reported as `.peek`
  with the same start and trigger distances, as fractions of trackpad height. It never fires;
  lifting always ends it with `.cancelled`. Fingers moving up are a swipe up whatever
  `naturalScroll` says. A swipe down still cancels the gesture.
- **Workspace overlay data.** Each swipe up runs `aerospace list-windows --all --json` once,
  shows the result with the previews from last time, then captures new previews and updates in
  place. Only workspaces whose name is a number are shown, and `list-windows` never mentions
  empty ones. If `aerospace` fails the overlay does not appear.
- **Previews need Screen Recording permission.** They come from ScreenCaptureKit
  (`CGWindowListCreateImage` is obsolete in the macOS 15 SDK). Without the permission, or for
  any window that fails to capture, the tile shows the window's title instead. The app asks at
  launch, and macOS asks again now and then about bypassing its window picker. The bundle is
  ad-hoc signed, so every `scripts/bundle.sh` build is a new app to the permission system and
  has to be granted again.
- **Previews are tiled, not positioned.** AeroSpace parks the windows of hidden workspaces
  off-screen, so their real positions say nothing; each square lays its windows out in a grid.
- **Aborted swipes retreat, then fade.** On release below the trigger the arrow slides back to
  its edge and only then does the box fade. A fired swipe just fades.
- **PATH.** Apps launched from Finder lack Homebrew on `PATH`. At startup the app asks the
  login shell for its `PATH` once (`printenv PATH`, which also works in fish) and runs every
  command through `/bin/sh -c` with it. Commands are therefore POSIX sh, not the user's shell.
- **Stdin is a pseudo-terminal.** Commands get a pty as stdin because some tools, AeroSpace
  0.20+ included, refuse to run with a non-TTY stdin. Stdout and stderr are discarded; a
  non-zero exit is logged with `NSLog`.
- **`Settings` name clash.** SwiftUI also exports `Settings`; the app target has a typealias
  in `SettingsWindow.swift` to pick ours.
- **System gesture conflict.** macOS's own four-finger swipes (System Settings → Trackpad →
  More Gestures → "Swipe between full-screen applications" and "Mission Control") must be off
  or set to three fingers, or both will react.
- The HUD uses `NSGlassEffectView` on macOS 26+ and falls back to `NSVisualEffectView`.

No README, by request.
