# Conga

A macOS menu bar app for switching AeroSpace workspaces with a four-finger trackpad swipe.
Swiping four fingers sideways or up fades in a glass row of squares, one per numbered AeroSpace
workspace that has windows, each showing previews of its windows with the workspace number over them.
The focused workspace is outlined; moving the fingers sideways moves the outline along the row,
and lifting switches to the outlined workspace. A sideways swipe released before the row is
fully shown, or swiped back, cancels. Swiping while a click is held on a window carries that
window instead: releasing the click moves it to the outlined workspace.

## Commands

```sh
swift build            # debug build
scripts/test.sh        # unit tests (extra args are passed to `swift test`)
scripts/bundle.sh      # release build wrapped in build/Conga.app, ad-hoc signed
open build/Conga.app
build/Conga.app/Contents/MacOS/Conga --preview-workspaces 1     # hold the workspace overlay fully shown
build/Conga.app/Contents/MacOS/Conga --log-touches > build/touches.log   # record raw touches and clicks (quit the running app first)
```

Use `scripts/test.sh` rather than bare `swift test`: the machine this was built on has only
the Command Line Tools (no Xcode), where SwiftPM does not find the Swift Testing macro plugin
by itself. For the same reason there is no Xcode project and no XCTest; tests use Swift Testing.

CI (`.github/workflows/test.yml`) runs `scripts/test.sh` on a `macos-26` runner for pushes to
`main` and for pull requests.

## Layout

- `Sources/CongaCore` — all logic, no AppKit. Everything here is unit tested.
  - `GestureRecognizer` — touch frames → `.peek` / `.peekReleased` / `.cancelled`.
  - `GestureDispatcher` — one recognizer per trackpad; seeks, switches workspaces, carries
    windows, emits overlay updates.
  - `Settings`, `SettingsStore` — values, clamping, `UserDefaults` persistence.
  - `ShellCommandRunner` — `/bin/sh -c`, fire and forget, `output(of:)` to read stdout, or
    `lines(of:)` to follow it line by line.
  - `ScrollFilter` — which scroll and gesture events to drop while the workspace overlay is open.
  - `ClickFilter` — which drags to drop, and when to move the mouse-up, for a carried window's click.
  - `WorkspaceOverview` — `aerospace` JSON → workspaces and their windows, the overlay's
    geometry, and `WorkspaceSeeker`, which turns sideways travel into a selected workspace.
- `Sources/Conga` — the AppKit/SwiftUI shell: status item, settings window, the HUD panel
  (`WorkspaceOverlayWindow`, styled by `HUDStyle`), `WindowPreviews`,
  `InputTap`, and `MultitouchMonitor`. Keep it thin; it has no tests.
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
  thresholds in `Settings` are fractions of trackpad width (or height, for a swipe up), and
  the settings UI shows percent.
- **Sideways swipes.** The overlay fades in between the indicator start distance
  (`Settings.indicatorStartFraction`) and half the trigger distance (`triggerFraction` ×
  `Settings.sidewaysTriggerScale`, never below the start), so seeking keeps most of the
  trackpad's width; the full trigger distance applies to a swipe up. Releasing before the trigger, or
  swiping back until it has faded out, cancels. Once past the trigger the overlay stays fully
  shown, all sideways movement from the trigger point seeks (swiping back moves the outline
  back rather than fading), and lifting switches. After a gesture ends the recognizer ignores
  input until every finger has lifted.
- **Natural scroll.** `Settings.naturalScroll` (off by default) reverses seeking: fingers
  moving left move the outline right. The recognizer always reports where the fingers went;
  `GestureDispatcher` flips it, for swipes up and sideways alike.
- **One direction per touch.** The direction is fixed once the swipe passes the indicator
  start distance. Swiping back past the starting point before the overlay is fully shown only
  undoes the swipe; it never starts one in the opposite direction until the fingers lift and
  touch again. The starting point follows the fingers while they are behind it, so swiping in
  the original direction again starts from where they turned around.
- **Palms.** MultitouchSupport labels each contact (`MTTouch.fingerID`, carried as `Touch.part`):
  1 thumb, 2–5 fingers, 6–7 palm. The recognizer drops palm-labelled touches before anything
  else, so a palm resting on the trackpad neither counts as a finger nor blocks a swipe.
  Measured with `--log-touches`, the label is set from a palm's first frame, while it is still
  fingertip-sized; size alone cannot separate a palm from the thumb. As a backstop for
  contacts the label misses, the recognizer also follows the four touches that started a
  gesture, by identifier, and positions come from those alone. Once the direction is fixed, any other touch (a palm
  brushing the trackpad) is ignored instead of shifting the centroid or cancelling; lifting
  one of the four ends the gesture. While seeking (a swipe up, or sideways past the trigger)
  it stays held while three of the four are down, because seeking slides fingers off the
  trackpad's edge; the frame a finger lifts counts
  as no movement, so the centroid jumping to the other three neither seeks nor fades. Before the direction is fixed a fifth touch still cancels,
  so five fingers put down together never swipe.
- **Up is a direction, down is not.** A swipe up locks the same way and is reported as `.peek`,
  fading in between the same start and trigger distances, as fractions of trackpad height.
  Fingers moving up are a swipe up whatever `naturalScroll` says. A swipe down cancels the
  gesture; once a sideways swipe is recognised, vertical movement is ignored.
- **A swipe up has no trigger distance.** Lifting anywhere past the indicator start distance,
  that is, while the overlay is at all visible, switches to the outlined workspace
  (`aerospace workspace <name>`, not configurable). Swiping back down until it has faded out
  cancels. Nothing runs if the outline is still on the focused workspace. Once the swipe up is
  recognised, a frame in which the fingers move more sideways than up or down does not change
  how far up the swipe is, so seeking with a hand that is not level does not fade the overlay;
  moving mostly down still does.
- **Seeking.** Once a swipe up is recognised, or a sideways swipe passes its trigger, every
  tenth of the trackpad's width the fingers move sideways moves the outline one workspace, in
  the direction of the fingers (reversed by `naturalScroll`). The row does not wrap; pushing past an end drags the starting point
  along, like a swipe. If the focused workspace is not in the row (it has a name, not a
  number), nothing is outlined until the fingers move.
- **Seeking accelerates.** Like the pointer, each frame's sideways movement is multiplied by
  `1 + Settings.workspaceAcceleration × speed`, the speed in trackpad widths per second above
  0.2, smoothed over about 40 ms and capped at 8×, so a slow movement still steps one workspace
  per tenth and a quick one jumps several. The speed comes from `TouchFrame.timestamp`; frames
  with equal timestamps, as in most tests, are never accelerated. 0 in the settings turns it off.
- **Workspace overlay data.** Each gesture that shows it runs `aerospace list-windows --all --json` once,
  shows the result with the previews from last time, then captures new previews and updates in
  place. Only workspaces whose name is a number are shown: those with windows, the focused
  one, and the lowest-numbered empty one on each monitor, so there is always somewhere new
  to switch to. They are grouped by monitor (`aerospace list-workspaces --all` gives each
  workspace's monitor ID), monitors in ID order and numbers in order within each, and the
  row leaves an extra half square between one monitor's group and the next; seeking crosses
  the gap like any other step. If `aerospace` fails the overlay does not appear. `GestureDispatcher.workspaces`
  holds the same list for seeking, so until a gesture's refresh arrives, a few tens of
  milliseconds in, it selects from the previous swipe's list.
- **Focus is followed between swipes.** So that the overlay never opens on a workspace that was
  focused before something else switched, the app keeps `aerospace subscribe
  focused-workspace-changed` running and moves the focus in the cached list as events arrive.
  `subscribe` needs AeroSpace 0.21; when it fails or exits, the app retries with a growing
  delay, and meanwhile opening the overlay empties the cached list, so no outline appears until the
  refresh says which workspace is focused, and then it fades in.
- **Previews need Screen Recording permission.** They come from ScreenCaptureKit
  (`CGWindowListCreateImage` is obsolete in the macOS 15 SDK). Without the permission, or for
  any window that fails to capture, the tile shows the window's title instead. The app asks at
  launch, and macOS asks again now and then about bypassing its window picker. The bundle is
  ad-hoc signed, so every `scripts/bundle.sh` build is a new app to the permission system and
  has to be granted again.
- **The overlay swallows scrolling.** MultitouchSupport only observes, so the fingers that
  seek along the overlay also scroll the window under the pointer. While the overlay is up,
  `InputTap` drops scroll and trackpad gesture events with a `CGEventTap`, and after it
  closes keeps dropping that scroll's remaining phases and momentum until a new scroll starts.
  The tap is enabled only while there is something to drop, and runs on its own thread: while
  it is enabled the window server holds every scroll event until it answers, and waiting on
  the main thread, busy drawing the overlay, froze the overlay and the gestures. A tap that drops events needs
  Accessibility permission, asked for at launch; without it scrolling passes through (the
  log says so), the taps are created as soon as it is granted (checked every 2 s) or the overlay opens, so granting needs no restart, and
  like Screen Recording it has to be granted again after each `scripts/bundle.sh`. Scrolling
  before the overlay starts to show (under the indicator start distance) still gets through.
- **Carrying a window.** `InputTap` has a second tap, for the left button, enabled whenever
  Conga is. While a click is held, `GestureDispatcher.clickBegan` takes the touches down at
  that moment as the clicking finger and leaves them out of every frame until they lift, so
  four more fingers make an ordinary swipe. When those four come down the app picks the
  frontmost layer-0 window under the click (`CGWindowListCopyWindowInfo`; nothing if a menu or
  panel is on top) and neutralises the click, unless the pointer has already moved more than
  `ClickFilter.dragSlop` with the button down, in which case the click is the app's drag and
  the swipe switches workspaces as usual. A neutralised click's drags are dropped, and its
  mouse-up is delivered outside the window (its screen's top-left corner, or far off-screen)
  so buttons and links cancel; the pointer is warped back if it followed. What an app does on
  mouse-down still happens. Lifting the four fingers keeps the overlay open; four put down
  again seek at once (`GestureRecognizer.startsSeeking`) from the outline
  (`WorkspaceSeeker.resume`). Releasing the click after they lift runs
  `aerospace move-node-to-workspace --window-id <id> --focus-follows-window <name>`, unless
  the outline is on the window's own workspace; releasing it with the fingers down, or a
  sideways swipe cancelled before the trigger, leaves the window where it is.
- **Previews are tiled, not positioned.** AeroSpace parks the windows of hidden workspaces
  off-screen, so their real positions say nothing; each square lays its windows out in a grid.
- **PATH.** Apps launched from Finder lack Homebrew on `PATH`. At startup the app asks the
  login shell for its `PATH` once (`printenv PATH`, which also works in fish) and runs every
  `aerospace` command through `/bin/sh -c` with it.
- **Stdin is a pseudo-terminal.** Commands get a pty as stdin because some tools, AeroSpace
  0.20+ included, refuse to run with a non-TTY stdin. Stdout and stderr are discarded; a
  non-zero exit is logged with `NSLog`.
- **`Settings` name clash.** SwiftUI also exports `Settings`; the app target has a typealias
  in `SettingsWindow.swift` to pick ours.
- **System gesture conflict.** macOS's own four-finger swipes (System Settings → Trackpad →
  More Gestures → "Swipe between full-screen applications" and "Mission Control") must be off
  or set to three fingers, or both will react.
- The overlay uses `NSGlassEffectView` on macOS 26+ and falls back to `NSVisualEffectView`.

No README, by request.
