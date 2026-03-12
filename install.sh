#!/bin/bash
set -euo pipefail

# Claude Central Station installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jgodwin-ai/central-station/main/install.sh | sh

APP_NAME="Claude Central Station"
EXECUTABLE="CentralStation"
BUNDLE_ID="com.jgodwin-ai.claude-central-station"
REPO="https://github.com/jgodwin-ai/central-station.git"
INSTALL_DIR="/Applications"
CLI_NAME="central-station"
CLI_DIR="/usr/local/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} ${BOLD}$1${NC}"; }
ok()    { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
warn()  { echo -e "${YELLOW}==>${NC} $1"; }
fail()  { echo -e "${RED}ERROR:${NC} $1"; exit 1; }

# --- Pre-flight checks ---

info "Installing $APP_NAME..."

# macOS only
if [ "$(uname)" != "Darwin" ]; then
    fail "$APP_NAME only runs on macOS."
fi

# Check for Swift toolchain
if ! command -v swift &>/dev/null; then
    fail "Swift toolchain not found. Install Xcode or Xcode Command Line Tools:\n  xcode-select --install"
fi

# Check for git
if ! command -v git &>/dev/null; then
    fail "git not found. Install Xcode Command Line Tools:\n  xcode-select --install"
fi

# Check Swift version (need 6.0+)
SWIFT_VERSION=$(swift --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
SWIFT_MAJOR=$(echo "$SWIFT_VERSION" | cut -d. -f1)
if [ "$SWIFT_MAJOR" -lt 6 ] 2>/dev/null; then
    warn "Swift $SWIFT_VERSION detected. Swift 6.0+ recommended. Build may fail."
fi

# --- Clone and build ---

WORK_DIR=$(mktemp -d -t central-station-install)
cleanup() {
    if [ -d "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/* || "$WORK_DIR" == /var/folders/* ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

info "Cloning repository..."
git clone --depth 1 "$REPO" "$WORK_DIR/central-station" 2>&1 | tail -1

info "Building release binary (this may take a minute)..."
cd "$WORK_DIR/central-station/app"
swift build -c release 2>&1 | grep -E '(Building|Build complete|error:)' || true

BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"

if [ ! -f "$BINARY" ]; then
    fail "Build failed. Check that you have Xcode or Command Line Tools installed."
fi

# --- Create app bundle ---

info "Creating app bundle..."
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$WORK_DIR/central-station/app/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Get version from git
VERSION=$(cd "$WORK_DIR/central-station" && git describe --tags 2>/dev/null || echo "0.1.0")

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

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# --- Install ---

info "Installing to $INSTALL_DIR..."

# Move old version to trash if present
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    warn "Moving existing installation to Trash."
    mv "$INSTALL_DIR/$APP_NAME.app" "$HOME/.Trash/$APP_NAME.app.$(date +%s)" 2>/dev/null || true
fi

cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

# --- CLI wrapper ---

info "Installing CLI command..."

# Create a wrapper script that launches the app or runs in a directory
CLI_WRAPPER="$CLI_DIR/$CLI_NAME"

# Need sudo for /usr/local/bin
if [ -w "$CLI_DIR" ]; then
    cat > "$CLI_WRAPPER" << 'WRAPPER'
#!/bin/bash
open -a "Claude Central Station" --args "$@"
WRAPPER
    chmod +x "$CLI_WRAPPER"
else
    sudo mkdir -p "$CLI_DIR"
    sudo tee "$CLI_WRAPPER" > /dev/null << 'WRAPPER'
#!/bin/bash
open -a "Claude Central Station" --args "$@"
WRAPPER
    sudo chmod +x "$CLI_WRAPPER"
fi

# --- Done ---

echo ""
ok "$APP_NAME installed successfully!"
echo ""
echo "  Open from:     Spotlight, Launchpad, or /Applications"
echo "  CLI:           central-station"
echo "  From a repo:   cd your-project && central-station"
echo ""
echo "  On first launch, you'll be prompted to install Claude Code hooks."
echo ""
