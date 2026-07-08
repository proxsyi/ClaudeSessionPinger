# Changelog

## v1.5.1

- Fixed a blank "Session Pinger Settings" window that could appear on launch: it was the leftover empty SwiftUI settings scene, which is now closed automatically so only the real Settings window ever shows.
- The Settings Updates section now shows the current app version and is separated by a divider.

## v1.5.0

- Added real auto-updating: the app now checks this repo's public GitHub Releases and can download, install, and relaunch itself into a new version with one click ("Install & Restart") -- no more manual rebuilds to pick up a new release, and no token or login needed.
- Added `Scripts/release.sh`, which builds the app, zips it, tags the current version, and publishes it as a GitHub release with that zip attached, so one script call ships an update.

## v1.4.2

- Removed manual `WKProcessPool` sharing in the login web view -- deprecated since macOS 12 and no longer had any effect, so it was just dead code producing build warnings.
- Settings now defaults the model slug to Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) instead of leaving it blank, including for installs that had already saved an empty value.
- Fixed the Settings schedule rows so the time stepper and remove button line up in a column instead of shifting based on the time label's width.
- Fixed Settings buttons (including "Check for updates") sometimes rendering as an empty shape with no visible label, by wrapping the Settings view in a `GlassEffectContainer` like the menu bar popover already does.

## v1.4.1

- Settings now only toggles with Cmd+, -- removed the Ctrl+, variant of the shortcut to avoid clashing with other apps' own Ctrl+, bindings.

## v1.4.0

- Added a real app icon: a hand-styled pixel-art stopwatch on the house icon design (rounded panel, greyish-teal border, Claude-orange face), replacing the generic default icon in Finder and Launchpad.
- Pressing Cmd+, now opens Settings from the menu bar popover, and closes Settings again when it's already open -- no need to reach for the mouse.
- Added the groundwork for update checks: the app can now check a version feed once a day and show a "Version X is available" banner with a download link, both in the menu bar and in Settings. Real checking is off until a release feed is hosted somewhere -- see the note in `UpdateChecker.swift`.

## v1.3.0

- Schedule times now show as a normal 12-hour clock (e.g. "5:00 AM", "3:00 PM") instead of 24-hour notation.
- Moved "Test connection", "Cancel", and "Save" into a fixed bar at the bottom of Settings so they're always fully visible and clickable instead of potentially sitting below the fold in the scrolling area; the Settings window is also resizable now.
- The built-in Claude login screen loads noticeably faster on repeat opens by reusing a warmed-up web engine process instead of starting a fresh one every time, and no longer runs Web Inspector instrumentation in the shipped build.

## v1.2.2

- Fixed: logging in through the built-in browser sometimes finished before claude.ai had set its organization cookie, so the app came back with a session but no organization ID. Login now waits a few seconds for that cookie before finishing.
- If the organization ID still can't be detected automatically after logging in, Settings now shows a clear note explaining how to find and paste it manually.

## v1.2.1

- Fixed a release build failure on Xcode 27 / Swift 6 strict concurrency checking: `AppDelegate` wasn't isolated to the main actor, so its lazy `AppState` property (which is main-actor-isolated) failed to initialize. `AppDelegate` is now explicitly `@MainActor`.
- Fixed a related concurrency warning where the login screen's cookie-polling timer called a main-actor method from a non-isolated timer callback.
- Fixed: a scheduled ping that fails because credentials aren't configured yet no longer leaves the menu bar countdown stuck; it now reschedules and sends a failure notification like every other failure path.
- Fixed: an OAuth sign-in popup (e.g. "Continue with Google") could spuriously flip the main login screen into a loading/error state from its own unrelated navigation events; popup and main window navigation are now tracked separately.
- Fixed: closing an OAuth sign-in popup with its native close button (instead of the page closing itself) could leave it tracked internally after the window was gone; closing the login screen while a popup is still open now closes that popup too.
- Made the Settings window's "Cancel" and "Test connection" buttons visually consistent with the rest of the glass UI.

## v1.2.0

- Replaced `MenuBarExtra(.window)` with a proper `NSStatusItem` + `NSPopover` (transient behavior), so clicking outside the menu bar popover now dismisses it, matching standard macOS menu bar app behavior.
- Settings is now a real, independently managed `NSWindow` instead of a sheet, avoiding SwiftUI window-scene ambiguity.
- Fixed built-in Claude login: added a realistic desktop Safari user agent, popup-window support for "Continue with Google"-style SSO flows, loading/error states with a retry action, and an inspectable web view for debugging.
- Applied a translucent, layered "glass" visual style (materials, soft gradient borders, tinted glass buttons) across the popover and settings UI, in the Claude accent palette.
- Removed the unused legacy `MenuBarLabel` SwiftUI view in favor of AppKit-managed status item icons.

## v1.0.0

- Initial release.
- Menu bar app (no Dock icon) that pings claude.ai on a configurable daily schedule (default 5am, 10am, 3pm, 8pm).
- Countdown to the next scheduled session shown in the menu bar popover.
- Success/failure tracking with a persisted history and running success rate.
- Session key stored in the macOS Keychain, never in plain text.
- Automatic retry with exponential backoff for transient network/server errors.
- Distinct handling for expired session keys, rate limiting, and server errors.
- Local notification on failed pings.
- Recovers correctly after sleep/wake and system time zone changes.
- Launch-at-login toggle.
- In-app settings screen with a test-connection action.
