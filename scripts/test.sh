#!/bin/zsh
set -eu
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p build evidence
swiftc Sources/Localization.swift Sources/CaptureGeometry.swift Tests/GeometryRuntimeMain.swift -o build/geometry-tests
build/geometry-tests
swiftc -swift-version 5 Sources/Localization.swift Sources/Export.swift Tests/ExportRuntimeMain.swift -o build/export-tests
build/export-tests
swiftc -swift-version 5 Sources/Localization.swift Sources/Clipboard.swift Tests/ClipboardRuntimeMain.swift -o build/clipboard-tests
build/clipboard-tests
swiftc -swift-version 5 Sources/Localization.swift Sources/Export.swift Sources/StickerLibrary.swift Sources/AnnotationStyle.swift Sources/AnnotationInspector.swift Sources/ImageEditor.swift Sources/ImageProcessing.swift Sources/ImageIntelligence.swift Tests/ImageRuntimeMain.swift -o build/image-tests
build/image-tests
swiftc -swift-version 5 Sources/Localization.swift Sources/ImageIntelligence.swift Tests/RecognitionRuntimeMain.swift -o build/recognition-tests
build/recognition-tests
localization_app=build/localization-tests.app
mkdir -p "$localization_app/Contents/MacOS" "$localization_app/Contents/Resources"
cp resources/Info.plist "$localization_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.screenshotking.localization-tests' "$localization_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable localization-tests' "$localization_app/Contents/Info.plist"
for localization in resources/*.lproj; do
    ditto "$localization" "$localization_app/Contents/Resources/${localization:t}"
done
swiftc Sources/Localization.swift Tests/LocalizationRuntimeMain.swift -o "$localization_app/Contents/MacOS/localization-tests"
"$localization_app/Contents/MacOS/localization-tests" -AppleLanguages '(en)' en
"$localization_app/Contents/MacOS/localization-tests" -AppleLanguages '(zh-Hans)' zh-Hans
"$localization_app/Contents/MacOS/localization-tests" -AppleLanguages '(fr)' en
