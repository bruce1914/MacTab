# Compatibility

- Apps must expose usable Accessibility windows. Some custom, protected, or system windows cannot be listed or focused.
- Windows are ordered by focus events observed while MacTab is enabled. Older focus history cannot be recovered on first enable.
- Minimized/offscreen windows and windows in other Spaces may have icon-only cards. Focusing across Spaces and full-screen spaces depends on macOS and the target app; it is not guaranteed.
- Ambiguous preview matches use an icon rather than showing another window's content. Protected content may appear blank.
- RealVNC windows are separate candidates if RealVNC exposes them through Accessibility. Each viewer version and connection mode still needs testing.
- When a Parallels process is frontmost, MacTab disables its shortcut tap. Guest key mappings remain controlled by Parallels. MacTab does not change them.
- Secure Input, revoked permissions, or event-tap failures suspend interception. The menu shows the state; pause and re-enable after correcting the permission problem.
- Only one running MacTab instance is allowed. The app has no updater and does not add itself to login items.

## What has been tested

Version 0.1.0 was built and run on macOS 14.8.9 / Apple Silicon. All 22 automated tests passed. The local user confirmed real window thumbnails, immediate left-click activation, and Command+Tab continuing to work inside Parallels Windows. The universal binary compiled for arm64 and x86_64; Intel hardware, other Macs, RealVNC, and cross-Space/full-screen integration have not been verified for this standalone release.

The automated suite covers frozen candidate order, repeated previous-window switching, reverse/wrap behavior, single/empty lists, pointer selection, Parallels bypass decisions, preview matching, cache eviction/release, gallery pagination, and click geometry. These tests do not replace macOS permission and real-window integration checks.

For a manual check, open two windows in one app and one window in another. Test quick switching back and forth, mouse focus followed by Command+Tab, reverse selection, Escape, hover and immediate click activation, closing a candidate, pause/quit, and switching inside Parallels. Check real thumbnails after granting Screen Recording. Test RealVNC and cross-Space/full-screen behavior separately if you rely on them.
