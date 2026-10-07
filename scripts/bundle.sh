#!/bin/sh
# Builds a release binary and wraps it in build/Conga.app.
set -eu

cd "$(dirname "$0")/.."

swift build -c release
app=build/Conga.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Conga" "$app/Contents/MacOS/Conga"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
