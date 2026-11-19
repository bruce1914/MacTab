# MacTab

**Windows-style Alt+Tab for your Mac — using Command+Tab.**

Switch between individual windows, including multiple windows from the same app, with a compact thumbnail gallery. Built with Swift and AppKit. No subscriptions, ads, telemetry, or third-party dependencies.

## Features

- Window-level recent-use order, including focus changes made with the mouse.
- Quick Command+Tab switches to the previous window; repeat to switch back.
- Hold Command and press Tab to advance, or Shift+Tab to go backward.
- Release Command to activate the selected window. Escape cancels.
- Hover gives a separate outline without changing the keyboard selection. Left-click a card to switch immediately.
- App icons, app names, window titles, and optional thumbnail previews.
- Menu-bar controls for enable/pause, permissions, and quit.
- Parallels applications retain their own keyboard shortcuts.
- English interface. No automatic login startup.

## Downloads

See [Releases](https://github.com/bruce1914/MacTab/releases) for source and experimental universal app builds. Version 0.1.0 is an **unnotarized preview**, not a Developer ID distribution release. macOS may block a downloaded build; building from source is the recommended option until a notarized release is available.

## Requirements

macOS 14 or later. Building requires Xcode with the macOS SDK and Swift 5.9 or later. The code has no package dependencies. Native builds use your Mac's architecture; universal builds include Apple Silicon and Intel.

## Build and install

```sh
git clone https://github.com/bruce1914/MacTab.git
cd MacTab
swift test
./build.sh
mkdir -p "$HOME/Applications"
ditto dist/MacTab.app "$HOME/Applications/MacTab.app"
open "$HOME/Applications/MacTab.app"
```

The default build uses an ad-hoc signature. For repeat local builds, use a stable signing identity from your own Keychain so macOS can retain its permission decisions:

```sh
SIGNING_IDENTITY="Apple Development: YOUR NAME (TEAM)" ./build.sh
```

To build both architectures:

```sh
ARCHITECTURE=universal ./build.sh
```

Builds are written to `dist/MacTab.app`. Do not run two tools that both intercept Command+Tab at the same time.

## First run

MacTab starts paused on its first launch. Open its menu-bar settings and:

1. Click **Accessibility…** and allow **MacTab** in System Settings → Privacy & Security → Accessibility.
2. Optionally click **Window previews…** and allow **MacTab** under Screen Recording. Follow any macOS prompt to quit and reopen the app.
3. Click **Enable**.

If MacTab is absent from the permissions list, use the system's **+** button to add the installed app. Permissions belong to MacTab itself; permissions granted to another app do not carry over. Without Screen Recording, cards show app icons and switching remains available. Pausing or quitting removes the shortcut listener so macOS can handle Command+Tab normally.

## Privacy and memory

MacTab reads window metadata through Accessibility and keeps its recent-use list in memory. It does not record ordinary typed input, save window-title logs, send network requests, or collect work-time history. Settings are stored in the app's own preferences domain.

Previews are requested only while the gallery is open. Captures are serialized, sized at most 448 × 280 pixels, and cached up to 16 images / 8 MiB of raw image data. Dismissing the gallery clears that cache; any already-running system capture is discarded when it completes. This is a cache limit, not a limit on the entire app's RAM usage. Previews are never written to disk by MacTab.

## Compatibility and limitations

- Apps must expose usable Accessibility windows. Some custom, protected, or system windows cannot be listed or focused.
- Windows are ordered by focus events observed while MacTab is enabled. Older focus history cannot be recovered on first enable.
- Minimized/offscreen windows and windows in other Spaces may have icon-only cards. Focusing across Spaces and full-screen spaces depends on macOS and the target app; it is not guaranteed.
- Ambiguous preview matches use an icon rather than showing another window's content. Protected content may appear blank.
- RealVNC windows are separate candidates if RealVNC exposes them through Accessibility. Each viewer version and connection mode still needs testing.
- When a Parallels process is frontmost, MacTab disables its shortcut tap. Guest key mappings remain controlled by Parallels. MacTab does not change them.
- Secure Input, revoked permissions, or event-tap failures suspend interception. The menu shows the state; pause and re-enable after correcting the permission problem.
- Only one running MacTab instance is allowed. The app has no updater and does not add itself to login items.

## Release signing

Local development builds are not notarized distribution builds. A release intended for ordinary downloads should be signed with the maintainer's **Developer ID Application** certificate, notarized, and stapled before packaging. Apple Development and ad-hoc signatures do not provide that distribution approval. No certificates, credentials, or private history are included in this repository.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). This project does not ask users to disable Gatekeeper.

## Validation

Version 0.1.0 was built and run on macOS 14.8.9 / Apple Silicon. All 22 automated tests passed. The local user confirmed real window thumbnails, immediate left-click activation, and Command+Tab continuing to work inside Parallels Windows. The universal binary compiled for arm64 and x86_64; Intel hardware, other Macs, RealVNC, and cross-Space/full-screen integration have not been verified for this standalone release.

The automated suite covers frozen candidate order, repeated previous-window switching, reverse/wrap behavior, single/empty lists, pointer selection, Parallels bypass decisions, preview matching, cache eviction/release, gallery pagination, and click geometry. These tests do not replace macOS permission and real-window integration checks.

For a manual check, open two windows in one app and one window in another. Test quick switching back and forth, mouse focus followed by Command+Tab, reverse selection, Escape, hover and immediate click activation, closing a candidate, pause/quit, and switching inside Parallels. Check real thumbnails after granting Screen Recording. Test RealVNC and cross-Space/full-screen behavior separately if you rely on them.

## License

[MIT](LICENSE). Copyright © 2026 bruce1914.
