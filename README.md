# Session Pinger

A minimal macOS menu bar app that pings claude.ai on a schedule so you control when your usage sessions start and end. Built with Swift + SwiftUI, no external dependencies.

## Important caveats

- claude.ai (the consumer web app) has no public API. This app reuses your browser's `sessionKey` login cookie against claude.ai's internal, undocumented endpoints, the same trick browser usage-tracker extensions use. It is not an official or supported integration.
- Those endpoints can change anytime without notice, which would break pings until updated.
- Your `sessionKey` is equivalent to your login. The app stores it in the macOS Keychain and never writes it to disk in plain text or logs it. Don't share it with anyone.
- Automating the consumer chat app like this may not align with the product's consumer terms of service. This is a personal risk you're taking on for your own account.

## Features

- Lives only in the menu bar (no Dock icon).
- Click the menu bar icon to see a live countdown to the next scheduled session, your all-time success rate, and the last result.
- Configurable schedule (defaults to 5am, 10am, 3pm, 8pm) so your day splits into four sessions.
- "Ping now" button for a manual trigger any time.
- Automatic retry with exponential backoff on transient network/server errors; no retry on expired sessions or bad config, since retrying those can't succeed.
- Distinguishes error types: missing config, network failure, expired session key, rate limiting, server errors, unexpected responses.
- Persisted ping history (last 50) and success rate, stored in Application Support, survives restarts.
- Local notification when a ping fails.
- Recovers automatically after your Mac sleeps/wakes or the system time zone changes.
- Launch-at-login toggle, backed by `SMAppService`.
- Settings screen with a "Test connection" button that pings immediately using whatever you've typed, before you save.

## One-time setup: get your session key, org ID, and model slug

1. Open [claude.ai](https://claude.ai) in your browser and make sure you're logged in.
2. Open DevTools (`Cmd+Option+I` in Chrome) -> **Application** tab -> **Cookies** -> `https://claude.ai`.
3. Copy the value of the `sessionKey` cookie.
4. Copy the value of the `lastActiveOrg` cookie -- that's your organization ID. (It's also in the URL of any conversation, right after `/organizations/`.)
5. Switch to the **Network** tab, filter for `completion`. Start a new chat, pick **Haiku 4.5** from the model picker, send any message, then click the `completion` request and copy the `"model"` value from its request payload (looks like `claude-haiku-4-5-YYYYMMDD`). Model slugs change over time, so always confirm this way rather than guessing.

You'll paste all three into the app's Settings screen (session key goes straight into the Keychain, never a plain-text file).

## Building

Requires Xcode's command line tools (Swift 5.9+) and macOS 13 Ventura or newer.

```bash
cd ClaudeSessionPinger
swift build -c release
```

If that succeeds cleanly, you're good. To get a real double-clickable `.app`:

```bash
chmod +x Scripts/build_app.sh
./Scripts/build_app.sh
```

This builds a release binary, wraps it in a proper `.app` bundle with `Info.plist` (menu-bar-only, no Dock icon), and ad-hoc code-signs it so Gatekeeper doesn't block a local run. The result lands in `dist/Session Pinger.app` -- move it to `/Applications` and double-click to launch.

If `swift build` reports errors, send them my way and I'll fix the code.

### Important: don't just hit "Run" on the raw package in Xcode

If you open `Package.swift` in Xcode and click the Play button, Xcode runs the executable as a bare command-line binary straight out of `DerivedData` -- it is never wrapped into a real `.app` bundle. SwiftUI's `MenuBarExtra` and `UNUserNotificationCenter` both require genuine app-bundle context (a real `Info.plist`, a bundle identifier, registration with Launch Services). Without it you'll see a crash like:

```
*** Assertion failure in +[UNUserNotificationCenter currentNotificationCenter] ...
bundleProxyForCurrentProcess is nil ...
```

(The `com.apple.linkd.autoShortcut` / intents-framework warnings right before that crash are harmless system log noise from the same unbundled-process situation -- ignore them.)

Two ways to avoid this:

1. **Recommended for everyday use:** always launch via `./Scripts/build_app.sh` and open the resulting `dist/Session Pinger.app` (or move it to `/Applications`). Never launch it by pressing Run inside Xcode on the package.
2. **If you want to debug inside Xcode** (breakpoints, live console): create a normal Xcode App project instead of opening `Package.swift` directly -- `File > New > Project > macOS > App` (SwiftUI interface), then drag all files from `Sources/ClaudeSessionPinger/` into the new project's target, and check **"Application is agent (UIElement)"** in the target's Info settings instead of using the standalone `Resources/Info.plist`. Xcode will then produce and run a properly bundled `.app` on every Run, notifications included.

As a safety net, the app itself now detects when it isn't running inside a real bundle and simply skips notification setup instead of crashing -- so even a raw `swift run` will no longer bring the whole process down.

## First run

1. Launch the app. A small icon appears in your menu bar (a dashed circle when idle).
2. Click it, then click **Settings**.
3. Paste your session key, organization ID, and model slug. Adjust the schedule or message if you want. Optionally turn on **Launch at login**.
4. Click **Test connection** to confirm it works before saving.
5. Click **Save**. The popover now shows a live countdown to your next scheduled session.

## Notes on reliability

- If your session key expires (you get logged out in the browser, or claude.ai rotates it), pings will fail with a clear "session expired" message in the popover and a notification -- head back into Settings and paste a fresh one.
- `launchd`/`SMAppService` login items don't wake a sleeping Mac. If the Mac is asleep at a scheduled time, that ping is simply skipped; the next one still fires normally.
- Uninstalling: quit the app, delete it from `/Applications`, and optionally remove its stored data:
  ```bash
  rm -rf ~/Library/Application\ Support/ClaudeSessionPinger
  security delete-generic-password -s com.cash.claudesessionpinger -a sessionKey
  ```
