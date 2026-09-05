#!/bin/bash
# Builds Silica.app into ./dist
set -e
cd "$(dirname "$0")"

APP="dist/Silica.app"
VERSION="${SILICA_VERSION:-1.0.0}"
BUILD="${SILICA_BUILD:-1}"
# Fill these in when the release repository and Sparkle signing key are ready.
APPCAST_URL="${SILICA_APPCAST_URL:-https://github.com/crevxo/silica/releases/latest/download/appcast.xml}"
PUBLIC_ED_KEY="${SILICA_PUBLIC_ED_KEY:-2y+EBTsESNugIHKjOp2ZP2njrnJmFVhiNZ864aPZ2MM=}"
echo "==> compiling"
swift build -c release

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Silica "$APP/Contents/MacOS/Silica"

echo "==> icon"
cp Resources/Silica.icns "$APP/Contents/Resources/Silica.icns"

echo "==> Sparkle"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework was not found at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Silica"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Silica</string>
    <key>CFBundleDisplayName</key><string>Silica</string>
    <key>CFBundleExecutable</key><string>Silica</string>
    <key>CFBundleIdentifier</key><string>com.santiago.silica</string>
    <key>CFBundleIconFile</key><string>Silica</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>SUFeedURL</key><string>$APPCAST_URL</string>
    <key>SUPublicEDKey</key><string>$PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Silica keeps your notes as plain text files in a folder inside Documents. It only reads and writes that folder.</string>
    <key>NSHumanReadableCopyright</key><string>Personal build</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Plain Text</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key>
            <array><string>public.plain-text</string><string>net.daringfireball.markdown</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> signing"
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
