#!/bin/bash
#
# Builds LGTV Companion as a proper .app bundle + DMG.
#
# Usage: ./scripts/build-release.sh [--install] [--adhoc]
#   --install  After building, quit the running app, replace
#              /Applications/LGTV Companion.app and start the new one.
#   --adhoc    Sign ad hoc even though the local signing certificate is
#              missing. The Accessibility and System Audio grants are lost
#              with every build then. CI is always allowed to (CI=true).
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LGTV Companion"
BUNDLE_ID="com.lgtvcompanion.mac"
VERSION="1.2.0"
# Unique per build (UTC, minute resolution); the user-facing version stays VERSION.
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
QUIT_WAIT_SECONDS=15

# Sign with the local certificate when it exists (see
# scripts/create-signing-cert.sh): a stable identity keeps the Accessibility
# and System Audio permissions valid across updates.
SIGN_IDENTITY="${LGTV_SIGN_IDENTITY:-LGTV Companion Local Signing}"

# Keys macOS shows to the user when it asks for a permission. An empty one
# makes the app crash or the prompt fail silently, so the verify step checks them.
USAGE_DESCRIPTION_KEYS=(
    NSBluetoothAlwaysUsageDescription
    NSAudioCaptureUsageDescription
    NSLocalNetworkUsageDescription
)

DO_INSTALL=false
ALLOW_ADHOC=false
if [ -n "${CI:-}" ]; then ALLOW_ADHOC=true; fi
for arg in "$@"; do
    case "$arg" in
        --install) DO_INSTALL=true ;;
        --adhoc)   ALLOW_ADHOC=true ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--install] [--adhoc]"; exit 2 ;;
    esac
done

# Decide the signature before the slow build, so a missing certificate fails fast.
if security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    USE_LOCAL_IDENTITY=true
elif $ALLOW_ADHOC; then
    USE_LOCAL_IDENTITY=false
else
    echo "ERROR: signing identity \"$SIGN_IDENTITY\" not found."
    echo "An ad-hoc build loses the Accessibility and System Audio permissions."
    echo "Run ./scripts/create-signing-cert.sh once, or pass --adhoc to build anyway."
    exit 1
fi

echo "==> Building release binary…"
swift build -c release

BIN=".build/release/LGTVCompanion"
[ -f "$BIN" ] || { echo "Binary not found: $BIN"; exit 1; }

echo "==> Assembling app bundle…"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# App icon — copied directly so Bundle.main can find it in Contents/Resources/.
# The app no longer uses Bundle.module for icon lookup, so the SPM resource bundle
# is not required at runtime; we skip it silently if absent.
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
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <!-- Menu bar app: starts without Dock icon. WindowPresence switches to
         a regular app while a window is open. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>LGTV Companion uses Bluetooth to set the volume and Sub Out level of your Edifier speakers.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>LGTV Companion adjusts the volume of your Mac's sound when the TV cannot do it itself, for example with speakers on the TV's optical output.</string>
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

if $USE_LOCAL_IDENTITY; then
    echo "==> Code signing with \"$SIGN_IDENTITY\"…"
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    echo "==> Ad-hoc code signing (no local certificate; --adhoc or CI)…"
    codesign --force -s - "$APP"
fi

verify_bundle() {
    echo "==> Verifying the bundle…"
    local plist="$APP/Contents/Info.plist"

    codesign --verify --deep --strict "$APP" \
        || { echo "VERIFY FAILED: the code signature is invalid."; exit 1; }

    if $USE_LOCAL_IDENTITY; then
        # An ad-hoc signature has a cdhash requirement instead, which changes
        # with every build and invalidates the permission grants.
        local requirement
        requirement="$(codesign -d -r- "$APP" 2>&1)"
        grep -q "certificate leaf" <<< "$requirement" \
            || { echo "VERIFY FAILED: the designated requirement has no 'certificate leaf'."
                 echo "The app is not signed with \"$SIGN_IDENTITY\"."; exit 1; }
    else
        echo "    (ad hoc: skipped the certificate leaf check)"
    fi

    plutil -lint "$plist" >/dev/null \
        || { echo "VERIFY FAILED: Info.plist is not valid."; exit 1; }

    local key value
    for key in "${USAGE_DESCRIPTION_KEYS[@]}"; do
        value="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
        [ -n "$value" ] \
            || { echo "VERIFY FAILED: $key is missing or empty in Info.plist."; exit 1; }
    done
    echo "    signature, Info.plist and usage descriptions are fine."
}
verify_bundle

echo "==> Creating DMG…"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO \
    "$BUILD_DIR/LGTVCompanion-$VERSION.dmg"

install_app() {
    echo "==> Installing to $INSTALL_DIR…"
    if pgrep -x "$APP_NAME" >/dev/null; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        local waited=0
        while pgrep -x "$APP_NAME" >/dev/null && [ "$waited" -lt "$QUIT_WAIT_SECONDS" ]; do
            sleep 1
            waited=$((waited + 1))
        done
        if pgrep -x "$APP_NAME" >/dev/null; then
            echo "    $APP_NAME did not quit in ${QUIT_WAIT_SECONDS}s, terminating it."
            pkill -x "$APP_NAME" || true
            sleep 1
        fi
    fi
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    # ditto keeps the signature, extended attributes and permissions intact.
    ditto "$APP" "$INSTALL_DIR/$APP_NAME.app"
    open "$INSTALL_DIR/$APP_NAME.app"
}

echo ""
echo "Done:"
echo "  App: $APP (version $VERSION, build $BUILD_NUMBER)"
echo "  DMG: $BUILD_DIR/LGTVCompanion-$VERSION.dmg"
echo ""
if $DO_INSTALL; then
    install_app
else
    echo "Install: ./scripts/build-release.sh --install"
fi
