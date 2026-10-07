#!/bin/sh
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM does
# not find the Swift Testing macro plugin on its own, so point the compiler at it.
set -eu

cd "$(dirname "$0")/.."

plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
