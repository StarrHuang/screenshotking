#!/bin/zsh
set -eu
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p build/ScreenshotKing.app/Contents/MacOS build/ScreenshotKing.app/Contents/Resources
mkdir -p build/ScreenshotKing.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" resources/branding/screenshotking-logo-v1.png --out "build/ScreenshotKing.iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" resources/branding/screenshotking-logo-v1.png --out "build/ScreenshotKing.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/ScreenshotKing.iconset -o build/ScreenshotKing.app/Contents/Resources/ScreenshotKing.icns
swiftc -swift-version 5 -parse-as-library -Osize -target arm64-apple-macos15.0 Sources/*.swift -o build/ScreenshotKing.app/Contents/MacOS/ScreenshotKing
cp resources/Info.plist build/ScreenshotKing.app/Contents/Info.plist
for localization in resources/*.lproj; do
    ditto "$localization" "build/ScreenshotKing.app/Contents/Resources/${localization:t}"
done
touch build/ScreenshotKing.app
codesign --force --sign - --identifier local.screenshotking.app build/ScreenshotKing.app
echo "$task_root/build/ScreenshotKing.app"
