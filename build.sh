#!/bin/zsh
# Builds a native Apple Silicon "Policy Tree.app" into ./build
#   ./build.sh            build only
#   ./build.sh --install  build, then copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

NAME="Policy Tree"
APP="build/$NAME.app"
rm -rf build && mkdir -p build/obj/icon "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -module-name PolicyTreeApp \
  -framework AppKit -framework UniformTypeIdentifiers \
  Sources/*.swift -o build/obj/PolicyTree
cp build/obj/PolicyTree "$APP/Contents/MacOS/PolicyTree"

# Compiles the layered Icon Composer document: Assets.car gives macOS 26+ the live Liquid Glass
# icon (light, dark, clear, tinted); AppIcon.icns is the flat fallback for macOS 14 and 15.
xcrun actool Resources/AppIcon.icon --compile build/obj/icon \
  --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist build/obj/icon/partial.plist \
  --app-icon AppIcon --include-all-app-icons \
  --enable-on-demand-resources NO --development-region id \
  --target-device mac --minimum-deployment-target 14.0 --platform macosx > build/obj/icon/actool.log
cp build/obj/icon/Assets.car build/obj/icon/AppIcon.icns "$APP/Contents/Resources/"
# Interface translations, shared with the Windows app. The lproj folders tell AppKit which
# languages the app speaks, so its own text (Untitled, save panels) follows the setting.
cp windows/policytree/strings_en.json "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/id.lproj" "$APP/Contents/Resources/en.lproj"
print '"CFBundleName" = "Policy Tree";' > "$APP/Contents/Resources/id.lproj/InfoPlist.strings"
cp "$APP/Contents/Resources/id.lproj/InfoPlist.strings" "$APP/Contents/Resources/en.lproj/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PolicyTree</string>
  <key>CFBundleIdentifier</key><string>com.lemonspitz.policytree</string>
  <key>CFBundleName</key><string>Policy Tree</string>
  <key>CFBundleDisplayName</key><string>Policy Tree</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 @lemonspitz</string>
  <key>CFBundleDevelopmentRegion</key><string>id</string>
  <key>CFBundleLocalizations</key><array><string>id</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Policy Tree</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.lemonspitz.policytree.document</string></array>
      <key>NSDocumentClass</key><string>PolicyDocument</string>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>JSON</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.json</string></array>
      <key>NSDocumentClass</key><string>PolicyDocument</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.lemonspitz.policytree.document</string>
      <key>UTTypeDescription</key><string>Policy Tree</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>policytree</string><string>pohon</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e "if application \"$NAME\" is running then tell application \"$NAME\" to quit" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$NAME.app"
  ditto "$APP" "/Applications/$NAME.app"
  echo "Installed /Applications/$NAME.app"
fi
