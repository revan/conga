# Slide

A macOS menu bar app that runs a shell command on a four-finger horizontal trackpad swipe.
Swipe left runs one command, swipe right another (defaults switch AeroSpace workspaces).
While the fingers are down, an arrow in a glass box tracks progress; releasing past the
trigger distance runs the command, and swiping back before releasing cancels.

## Commands

```sh
swift build            # debug build
scripts/test.sh        # unit tests (extra args are passed to `swift test`)
scripts/bundle.sh      # release build wrapped in build/Slide.app, ad-hoc signed
open build/Slide.app
build/Slide.app/Contents/MacOS/Slide --preview-indicator 0.6   # hold the HUD at 60%; negative = left swipe
```

Use `scripts/test.sh` rather than bare `swift test`: the machine this was built on has only
the Command Line Tools (no Xcode), where SwiftPM does not find the Swift Testing macro plugin
by itself. For the same reason there is no Xcode project and no XCTest; tests use Swift Testing.

## Layout

- `Sources/SlideCore` — all logic, no AppKit. Everything here is unit tested.
  - `GestureRecognizer` — touch frames → `.progress` / `.fired` / `.cancelled`.
  - `GestureDispatcher` — one recognizer per trackpad; runs commands, emits indicator updates.
  - `IndicatorModel` — progress → opacity and arrow offset.
  - `Settings`, `SettingsStore` — values, clamping, `UserDefaults` persistence.
  - `ShellCommandRunner` — `/bin/sh -c`, fire and forget.
- `Sources/Slide` — the AppKit/SwiftUI shell: status item, settings window, HUD panel, and
  `MultitouchMonitor`. Keep it thin; it has no tests.
- `Sources/CMultitouch` — C declarations for the private framework. No code.
- `Tests/SlideCoreTests` — tests for `SlideCore`.

New behaviour goes in `SlideCore` with tests; the app target should only wire things together.

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
- **One direction per touch.** The direction is fixed once the swipe passes the indicator
  start distance. Swiping back past the starting point only undoes the swipe; it never starts
  one in the opposite direction until the fingers lift and touch again.
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
- **System gesture conflict.** macOS's own four-finger horizontal swipe (System Settings →
  Trackpad → More Gestures → "Swipe between full-screen applications") must be off or set to
  three fingers, or both will react.
- The HUD uses `NSGlassEffectView` on macOS 26+ and falls back to `NSVisualEffectView`.

No README, by request.
