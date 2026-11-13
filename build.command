#!/bin/zsh
set -eu
cd "${0:A:h}"
BUILD_ROOT="$(mktemp -d /private/tmp/powerlens-build.XXXXXX)"
APP="$BUILD_ROOT/PowerLens.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -O -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/powerlens-swift-cache" -framework AppKit -framework SwiftUI -framework IOKit Sources/*.swift -o "$APP/Contents/MacOS/PowerLens"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PowerLens</string>
<key>CFBundleIdentifier</key><string>local.kinson.PowerLens</string>
<key>CFBundleIconFile</key><string>PowerLens</string>
<key>CFBundleName</key><string>PowerLens</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.9.6</string>
<key>CFBundleVersion</key><string>16</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources"
cp Assets/PowerLens.icns "$APP/Contents/Resources/"
cp LICENSE-StatusTrio.txt NOTICE-StatusTrio.txt "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/PowerLens" --self-test

codesign --verify --verbose "$APP"
ditto --norsrc --noextattr "$APP" "$PWD/PowerLens.app"
printf "Built: %s\n" "$PWD/PowerLens.app"
