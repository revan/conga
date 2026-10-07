#!/bin/sh
# Builds a release binary and wraps it in build/Slide.app.
set -eu

cd "$(dirname "$0")/.."

swift build -c release
app=build/Slide.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Slide" "$app/Contents/MacOS/Slide"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
