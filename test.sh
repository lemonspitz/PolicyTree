#!/bin/zsh
# Tests for the model and layout (no AppKit, no window).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/obj
swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-name PolicyTreeTests Sources/Localization.swift Sources/Model.swift Sources/Layout.swift Tests/main.swift -o build/obj/tests
POLICYTREE_STRINGS=windows/policytree/strings_en.json build/obj/tests
# Every interface string in both apps must have an English entry.
python3 tools/i18n_check.py

# Real window, real events, inside the app process.
swiftc -swift-version 5 -D UITEST -target arm64-apple-macos14.0 -module-name PolicyTreeApp \
  -framework AppKit -framework UniformTypeIdentifiers \
  Sources/*.swift Tests/UITest.swift -o build/obj/uitest
T=build/obj/UITest.app
rm -rf "$T" && mkdir -p "$T/Contents/MacOS"
cp build/obj/uitest "$T/Contents/MacOS/PolicyTree"
cp Tests/UITest-Info.plist "$T/Contents/Info.plist"
"$T/Contents/MacOS/PolicyTree" --uitest
