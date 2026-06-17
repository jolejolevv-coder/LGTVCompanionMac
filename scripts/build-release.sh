#!/bin/bash
#
# Builds LGTV Companion as a proper .app bundle + DMG.
# Usage: ./scripts/build-release.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LGTV Companion"
BUNDLE_ID="com.lgtvcompanion.mac"
VERSION="1.0.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary…"
swift build -c release

BIN=".build/release/LGTVCompanion"
[ -f "$BIN" ] || { echo "Binary not found: $BIN"; exit 1; }

echo "==> Assembling app bundle…"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# App icon + SPM resource bundle. Bundle.module also checks
# Bundle.main.resourceURL (Contents/Resources) — placing it there keeps
# codesign happy (bundles inside Contents/MacOS break signing).
cp App/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -d ".build/release/LGTVCompanion_LGTVCompanionApp.bundle" ]; then
    cp -R ".build/release/LGTVCompanion_LGTVCompanionApp.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>LGTV Companion needs access to your local network to discover and control your LG WebOS TV.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_webos._tcp</string>
    </array>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing…"
codesign --force -s - "$APP"

echo "==> Creating DMG…"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO \
    "$BUILD_DIR/LGTVCompanion-$VERSION.dmg"

echo ""
echo "Done:"
echo "  App: $APP"
echo "  DMG: $BUILD_DIR/LGTVCompanion-$VERSION.dmg"
echo ""
echo "Install: cp -r \"$APP\" /Applications/"
