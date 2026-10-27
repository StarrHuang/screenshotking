#!/bin/zsh
set -eu
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p build evidence
swiftc Sources/CaptureGeometry.swift Tests/GeometryRuntimeMain.swift -o build/geometry-tests
build/geometry-tests
swiftc -swift-version 5 Sources/Export.swift Tests/ExportRuntimeMain.swift -o build/export-tests
build/export-tests
swiftc -swift-version 5 Sources/Clipboard.swift Tests/ClipboardRuntimeMain.swift -o build/clipboard-tests
build/clipboard-tests
swiftc -swift-version 5 Sources/Export.swift Sources/StickerLibrary.swift Sources/AnnotationStyle.swift Sources/AnnotationInspector.swift Sources/ImageEditor.swift Sources/ImageProcessing.swift Sources/ImageIntelligence.swift Tests/ImageRuntimeMain.swift -o build/image-tests
build/image-tests
swiftc -swift-version 5 Sources/ImageIntelligence.swift Tests/RecognitionRuntimeMain.swift -o build/recognition-tests
build/recognition-tests
