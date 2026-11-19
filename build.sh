#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
# Use a stable local signing identity to retain permissions across rebuilds.
signing_identity="${SIGNING_IDENTITY:--}"
architecture="${ARCHITECTURE:-native}"
build_args=(-c release)
case "$architecture" in
    native) ;;
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) build_args+=(--arch "$architecture") ;;
    *) echo "ARCHITECTURE must be native, universal, arm64, or x86_64" >&2; exit 1 ;;
esac
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app_dir="$project_dir/dist/MacTab.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MacTab" "$app_dir/Contents/MacOS/MacTab"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
sign_args=(--force --sign "$signing_identity" --options runtime)
if [[ "$signing_identity" == "-" ]]; then
    sign_args+=(--timestamp=none)
else
    sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "$app_dir"
codesign --verify --strict "$app_dir"
printf '%s\n' "$app_dir"
