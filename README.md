# Session Pinger

A tiny macOS menu bar app that sends claude.ai a scheduled message ("Say 1") so **you** control when your Claude usage sessions start and end -- instead of a session starting whenever you happen to send your first message of the day.

## What it does

- Pings claude.ai on your schedule (default: 5am, 10am, 3pm, 8pm) so your day splits into predictable session windows.
- Live usage in the menu bar popover: 5-hour session and weekly bars with reset times, plus Claude service status.
- Notifications for ping failures, Claude outages, degraded performance, and usage thresholds -- each individually toggleable.
- Auto-updates from GitHub Releases (toggleable).
- Lives only in the menu bar. No Dock icon.

## Get it running

1. Download the latest `Session.Pinger.zip` from [Releases](https://github.com/proxsyi/ClaudeSessionPinger/releases) and unzip it.
2. Drag `Session Pinger.app` into your **Applications** folder.
3. Open it. **macOS will block the first launch** with *"Apple could not verify 'Session Pinger' is free of malware"* and only offer "Move to Trash" or "Done". This is expected: the app is signed with a personal certificate, not through Apple's paid notarization program. One-time fix:
   - Click **Done** (not Move to Trash).
   - Open **System Settings > Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to Session Pinger, then confirm.
   - Terminal alternative that skips all of the above: `xattr -dr com.apple.quarantine "/Applications/Session Pinger.app"` and then open the app normally.
4. The first launch shows one keychain prompt ("Session Pinger wants to access key..."). Enter your Mac login password and click **Always Allow** -- it won't ask again, including after updates.
5. Click the sparkle in your menu bar > **Settings** > **Log in with Claude**. Your session and organization are captured automatically. Done.

## Good to know

- claude.ai has no public API. This app reuses your own login session against claude.ai's internal endpoints (the same trick browser usage-tracker extensions use). It is not an official integration, and those endpoints can change without notice, breaking pings until the app is updated.
- Your session credentials are stored only in the macOS Keychain -- never in plain text, never logged, never sent anywhere except claude.ai.
- Automating the consumer chat app may not align with its terms of service. That's a personal call for your own account.
- A sleeping Mac skips that scheduled ping; the next one fires normally.

## Building from source

Requires macOS 13+ and Xcode command line tools.

~~~bash
git clone https://github.com/proxsyi/ClaudeSessionPinger.git
cd ClaudeSessionPinger
./Scripts/build_app.sh
~~~

The app lands in `dist/Session Pinger.app` -- move it to /Applications. Don't run the raw package from Xcode's Play button: the app must run as a real `.app` bundle for the menu bar item and notifications to work.

## Uninstall

Quit the app, delete it from /Applications, then optionally:

~~~bash
rm -rf ~/Library/Application\ Support/ClaudeSessionPinger
security delete-generic-password -s com.cash.claudesessionpinger -a sessionKey
security delete-generic-password -s com.cash.claudesessionpinger -a cookieHeader
~~~
