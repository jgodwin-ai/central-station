#!/bin/bash
set -euo pipefail

APP_NAME="Claude Central Station"
BUNDLE_ID="com.jgodwin-ai.claude-central-station"
EXECUTABLE="CentralStation"
VERSION="${1:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/app"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building release binary..."
cd "$APP_DIR"
swift build -c release 2>&1

BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle..."
if [ -d "$APP_BUNDLE" ]; then
    mv "$APP_BUNDLE" "$BUILD_DIR/.old-app-bundle-$$"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary and icon
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$APP_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary directory for the DMG contents
DMG_STAGING=$(mktemp -d -t central-station-dmg)
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean up staging (safe — it's a mktemp dir)
if [[ "$DMG_STAGING" == /tmp/* || "$DMG_STAGING" == /var/folders/* ]]; then
    rm -rf "$DMG_STAGING"
fi

echo ""
echo "==> Done!"
echo "    App:  $APP_BUNDLE"
echo "    DMG:  $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
