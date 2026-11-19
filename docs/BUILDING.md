# Build MacTab

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

## Release signing

Local development builds are not notarized distribution builds. A release intended for ordinary downloads should be signed with the maintainer's **Developer ID Application** certificate, notarized, and stapled before packaging. Apple Development and ad-hoc signatures do not provide that distribution approval. No certificates, credentials, or private history are included in this repository.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). This project does not ask users to disable Gatekeeper.
