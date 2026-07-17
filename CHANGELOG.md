# Changelog

## v1.14.0

- Added an optional Fable 5 weekly usage bar with tolerant parsing for undocumented usage-payload key variants.
- Added Settings toggles for the session, weekly, and Fable 5 bars; session and weekly are visible by default.

## v1.13.0

- All scheduled, manual, and test pings now reuse one dedicated Claude chat instead of creating a new conversation every time.
- Added Settings actions to open the dedicated pinger chat or intentionally start fresh; a deleted chat is replaced automatically on the next ping.
- Updated notification authorization to the async macOS API, removing the Xcode 27 build warning.

## v1.12.0

- The menu bar icon now turns crimson at 100% session usage and shows a live countdown until the session resets.
- Moved success rate, the last ping result, errors, and the manual Ping now action from the popover into a new Settings Activity section.
- Replaced automatic model mode with a manual model picker. The selected model is always tried first, with detected and known models used as fallbacks if Claude rejects it.
- Added 25%, 50%, 75%, 90%, 95%, and 100% notification threshold choices for session and weekly usage.
- Aligned schedule times into fixed time and AM/PM columns.
- The main countdown now follows the next usable session when the current window is maxed out, with the next scheduled ping shown underneath.
- Re-runs the stable-signing keychain ownership repair once so legacy credentials stop asking for a password on later launches.
- Changed the personal app identity to `com.proxsyi.claudesessionpinger` and migrates existing settings and credentials from the legacy identity.
- Build output now removes post-signing Finder metadata and must pass strict signature verification before it is considered complete.

## v1.11.0

- Fixed the keychain password prompt reappearing after every update: the stored session entries were created by older ad-hoc-signed builds, so macOS never treated new builds as their owner. On first launch the app now re-creates its keychain entries under the stable signing identity (one final prompt during this migration, then never again).
- Settings window glass now extends under the title bar, removing the transparent strip and the doubled "Settings" title.
- Settings header clears the traffic-light buttons, and the scroll bar no longer draws on top of the content.

## v1.10.0

- Fixed usage notifications re-alerting limits that were already hit: the first fetch after launch now records existing usage silently, and server-side jitter in window reset timestamps no longer wipes the "already notified" memory (this was the source of the random repeat alerts).
- Ping-failure notifications now use a stable identifier so repeats replace the previous alert instead of stacking duplicates.
- The test notification button now requests notification permission on the spot when it was never granted, and reports delivery errors instead of failing silently.
- Clear Liquid Glass: panels now use the clear glass variant instead of frosted, and the Settings window background is far more transparent.
- Fixed Settings content clipping through the header and footer while scrolling.
- New 16x16 app icon following the house icon design rules (rounded panel, greyish-teal border with top highlight, Claude-orange face, outlined stopwatch symbol).
- README rewritten: simple explanation of what the app does, clean install steps, and how to get past Gatekeeper's "cannot verify" block on first launch.
- Release flow now removes the build copy of the app after publishing so Spotlight no longer shows duplicate Session Pingers.

## v1.9.0

- Complete visual refresh: the pixel/retro look is gone. The whole app -- popover, Settings, progress bars, and the menu bar icon -- is now clean, minimal Liquid Glass driven by the system's materials.
- Claude service alerts now distinguish full outages from degraded performance, using the severity reported by Claude's status page, and still announce recovery.
- Every notification type has its own toggle in Settings: ping failures, Claude services down, Claude performing poorly, and the individual usage thresholds.
- The menu bar icon is now a clean sparkle tinted by session usage instead of the pixel starburst; usage bars are smooth capsules instead of segmented blocks.
- Settings restyled with right-aligned switches, quieter typography, and capsule threshold pills.

## v1.8.0

- Settings reorganized: the organization ID and manual session key now live in a collapsed "Keys" area under Account -- they're captured automatically at login, so they stay out of the way.
- Logging in now captures every claude.ai cookie (not just the session key) and stores them in the keychain; all requests -- pings, usage, model detection, org lookup -- send the full cookie set, exactly like the browser session.
- Automatic model selection: the app detects which Claude models the account can use, prefers the lightest one, and switches automatically if claude.ai rejects a model. A toggle in Settings switches back to a fixed manual model slug.
- Added a "Send test notification" button in Settings, with a hint when macOS has notifications turned off for the app.
- Auto-update is now a toggle: when on, new releases install themselves as soon as the daily check finds one (each version is attempted once, so a failed install can't loop).
- The Settings window is now real behind-window Liquid Glass driven by the system's material settings (including Reduce Transparency), with a transparent title bar.
- Fixed scrolled Settings content drawing over the Test connection/Cancel/Save footer buttons.

## v1.7.0

- Full pixel/retro restyle layered on the existing Liquid Glass panels, keeping the Claude color palette: monospaced pixel typography, uppercase tracked section headers, square status dots, and chunky segmented "health bar" usage meters. The menu bar star is now true 16x16 pixel art, still color-coded by session usage (green/yellow/red).
- Settings redesigned into glass sections -- Account, Ping, Notifications, App, Updates -- to match everything the app now does.
- Logging in now always captures everything the app needs: if the organization cookie is slow to appear, the organization ID is fetched straight from claude.ai with the new session, and usage refreshes immediately after signing in.
- New notifications: Claude service outage and recovery alerts (toggleable), plus customizable session and weekly usage alerts -- pick any of the 50/75/90/95% thresholds in Settings, each firing at most once per usage window.
- All notifications now play a sound.

## v1.6.0

- Added ClaudeUsageBar-style Claude usage tracking to the menu bar popover: session (5-hour) and weekly (7-day) usage bars with reset times, read from the same claude.ai endpoint that powers claude.ai/settings/usage using the session key the app already stores, plus a Claude service status line and a manual Refresh button. Usage auto-refreshes every 5 minutes and when the popover opens.
- The menu bar item is now a 16x16 color-coded starburst (green under 70%, yellow from 70%, red from 90% session usage; gray while unknown) with the current session percentage shown next to it, replacing the old status circle icons. Ping status remains visible via the colored dot in the popover header.

## v1.5.3

- Fixed the menu bar icon not opening its popover: the launch-time cleanup that hides the stray empty Settings window was too broad and also closed the status item's own window. It now closes only the leftover "<App Name> Settings" window and leaves the menu bar item and popover alone.

## v1.5.2

- The build script now signs the app with a stable code-signing identity when one is available (falling back to ad-hoc otherwise), so once a signing certificate exists the macOS keychain stops re-prompting for access after every update.

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
