# Privacy and memory

MacTab reads window metadata through Accessibility and keeps its recent-use list in memory. It does not record ordinary typed input, save window-title logs, send network requests, or collect work-time history. Settings are stored in the app's own preferences domain.

Previews are requested only while the gallery is open. Captures are serialized, sized at most 448 × 280 pixels, and cached up to 16 images / 8 MiB of raw image data. Dismissing the gallery clears that cache; any already-running system capture is discarded when it completes. This is a cache limit, not a limit on the entire app's RAM usage. Previews are never written to disk by MacTab.
