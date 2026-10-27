import AppKit
import Darwin
import ImageIO
import SwiftUI

@MainActor @main enum ImageTests {
    static func main() throws {
        do {
        try testCropUsesTopLeftPixelCoordinates()
        try testCropSelectsAsymmetricTopAndBottomQuadrants()
        try testVerticalStitchFindsAndRemovesPixelExactOverlap()
        try testRetinaStitchPreservesLogicalDimensions()
        try testHorizontalStitchKeepsLeftToRightPixelOrder()
        try testStitchSupportsOverHalfOverlapWithRepeatedRows()
        try testStitchRejectsMismatchedCrossAxisDimensions()
        try testRendererCompositesAnnotationsIntoActualPixelImage()
        try testMosaicIsMaskedToTheSelectedPixels()
        try testCanvasUndoRedoRestoresCompositePixels()
        try testCropUndoRedoRestoresSourceAndAnnotations()
        try testNumberMouseDownMouseUpDoesNotCrash()
        try testCanvasDragPreviewRendersEffectsOffscreen()
        try testDocumentRoundTripAndNewUndoHistory()
        try testFramingAndOneXExportAffectRealPixels()
        try testRetinaAnnotationSizeAndExportPoints()
        try testLocalToolsAndCanvasExpansionUndo()
        try testHEICImageIOEncoding()
        try testQAFixtureOrientationAndWriteEvidence()
        try testEffectsReadTopLeftSourceCoordinates()
        try testAnnotationStyleMigrationAndRoundTrip()
        try testThemeResolvesExistingAnnotations()
        try testShapeArrowBrushAndWatermarkPixels()
        try testRectangularHighlightPixels()
        try testSpacePanShiftConstraintAndToolShortcuts()
        try testAccessibilityCanvasPressCreatesAndSavesText()
        try testHostedCanvasAXPressSavesNoteAndStep()
        try testSelectDragCopyDeleteUndoAndInlineText()
        try testStepDistinctionStickerPNGAndEvidenceSheet()
        print("ImageRuntimeMain: crop, vertical/horizontal stitching, editing, undo/redo, document reload, frame/scale export, and HEIC passed")
        } catch { fputs("ImageTests failed: \(error)\n", stderr); exit(1) }
    }

    static func testCropUsesTopLeftPixelCoordinates() throws {
        let source = try image(width: 4, height: 4) { x, y in
            [UInt8(x * 40), UInt8(y * 40), 10, 255]
        }
        let crop = try ImageProcessing.crop(image: source, rect: CGRect(x: 1, y: 0, width: 2, height: 1))
        let cg = try require(crop.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cg.width == 2 && cg.height == 1, "crop dimensions")
        let cropPixel = pixel(cg, x: 0, y: 0)
        try check(cropPixel == [40, 0, 10, 255], "crop top-left pixel was \(cropPixel)")
    }

    static func testCropSelectsAsymmetricTopAndBottomQuadrants() throws {
        let source = try image(width: 6, height: 6) { x, y in
            let top = y < 3
            let left = x < 3
            if top && left { return [255, 0, 0, 255] }
            if top { return [0, 255, 0, 255] }
            if left { return [0, 0, 255, 255] }
            return [255, 255, 0, 255]
        }
        let topLeft = try ImageProcessing.crop(image: source, rect: CGRect(x: 0, y: 0, width: 3, height: 3))
        let bottomLeft = try ImageProcessing.crop(image: source, rect: CGRect(x: 0, y: 3, width: 3, height: 3))
        let top = try require(topLeft.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bottom = try require(bottomLeft.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(top, x: 1, y: 1) == [255, 0, 0, 255], "top-left crop selects red quadrant")
        try check(pixel(bottom, x: 1, y: 1) == [0, 0, 255, 255], "bottom-left crop selects blue quadrant")
    }

    static func testVerticalStitchFindsAndRemovesPixelExactOverlap() throws {
        func strip(rows: ClosedRange<Int>) throws -> NSImage {
            try image(width: 8, height: rows.count) { x, localY in
                let row = rows.lowerBound + localY
                return [UInt8(row * 15), UInt8(x * 10), 40, 255]
            }
        }
        let stitched = try ImageProcessing.stitch(images: [strip(rows: 0...7), strip(rows: 4...11)], direction: .vertical)
        let cg = try require(stitched.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cg.width == 8 && cg.height == 12, "stitched dimensions were \(cg.width)x\(cg.height)")
        for y in 0..<12 { let value = pixel(cg, x: 2, y: y)[0]; try check(value == UInt8(y * 15), "stitched row \(y) was \(value)") }
    }

    static func testHorizontalStitchKeepsLeftToRightPixelOrder() throws {
        func strip(columns: ClosedRange<Int>) throws -> NSImage {
            try image(width: columns.count, height: 8) { localX, y in
                let column = columns.lowerBound + localX
                return [UInt8(column * 15), UInt8(y * 10), 40, 255]
            }
        }
        let stitched = try ImageProcessing.stitch(images: [strip(columns: 0...7), strip(columns: 4...11)], direction: .horizontal)
        let cg = try require(stitched.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cg.width == 12 && cg.height == 8, "horizontal stitched dimensions were \(cg.width)x\(cg.height)")
        for x in 0..<12 { let value = pixel(cg, x: x, y: 3)[0]; try check(value == UInt8(x * 15), "stitched column \(x) was \(value)") }
    }

    static func testStitchSupportsOverHalfOverlapWithRepeatedRows() throws {
        func signal(_ position: Int) -> UInt8 {
            position.isMultiple(of: 37) ? 245 : UInt8((position % 20) * 8)
        }
        let verticalFirst = try image(width: 32, height: 600) { x, y in [signal(y), UInt8((x * 5) % 256), UInt8((y % 20) * 8), 255] }
        let verticalSecond = try image(width: 32, height: 600) { x, y in [signal(y + 250), UInt8((x * 5) % 256), UInt8(((y + 250) % 20) * 8), 255] }
        let vertical = try ImageProcessing.stitch(images: [verticalFirst, verticalSecond], direction: .vertical)
        let verticalCG = try require(vertical.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(verticalCG.width == 32 && verticalCG.height == 850, "vertical stitch removes the 350px overlap (58.3% of input height), including repeated-looking rows: \(verticalCG.width)x\(verticalCG.height)")
        for y in 0..<850 { try check(pixel(verticalCG, x: 11, y: y) == [signal(y), 55, UInt8((y % 20) * 8), 255], "vertical repeated-row fixture preserves source row \(y)") }

        let horizontalFirst = try image(width: 600, height: 32) { x, y in [signal(x), UInt8((y * 5) % 256), UInt8((x % 20) * 8), 255] }
        let horizontalSecond = try image(width: 600, height: 32) { x, y in [signal(x + 250), UInt8((y * 5) % 256), UInt8(((x + 250) % 20) * 8), 255] }
        let horizontal = try ImageProcessing.stitch(images: [horizontalFirst, horizontalSecond], direction: .horizontal)
        let horizontalCG = try require(horizontal.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(horizontalCG.width == 850 && horizontalCG.height == 32, "horizontal stitch removes the 350px overlap (58.3% of input width), including repeated-looking columns: \(horizontalCG.width)x\(horizontalCG.height)")
        for x in 0..<850 { try check(pixel(horizontalCG, x: x, y: 11) == [signal(x), 55, UInt8((x % 20) * 8), 255], "horizontal repeated-column fixture preserves source column \(x)") }
    }

    static func testRetinaStitchPreservesLogicalDimensions() throws {
        let upperPixels = try image(width: 8, height: 6) { x, y in [UInt8(y * 20), UInt8(x * 10), 30, 255] }
        let lowerPixels = try image(width: 8, height: 6) { x, y in [UInt8((y + 6) * 20), UInt8(x * 10), 30, 255] }
        let upper = NSImage(cgImage: try require(upperPixels.cgImage(forProposedRect: nil, context: nil, hints: nil)), size: NSSize(width: 4, height: 3))
        let lower = NSImage(cgImage: try require(lowerPixels.cgImage(forProposedRect: nil, context: nil, hints: nil)), size: NSSize(width: 4, height: 3))
        let stitched = try ImageProcessing.stitch(images: [upper, lower], direction: .vertical)
        let cg = try require(stitched.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cg.width == 8 && cg.height == 12, "retina stitch retains raster pixels")
        try check(stitched.size == NSSize(width: 4, height: 6), "retina stitch preserves input point scale: \(stitched.size)")
        for y in 0..<12 { try check(pixel(cg, x: 2, y: y)[0] == UInt8(y * 20), "retina stitch keeps row order at y=\(y)") }
    }

    static func testStitchRejectsMismatchedCrossAxisDimensions() throws {
        let a = try image(width: 4, height: 8) { _, _ in [0, 0, 0, 255] }
        let verticalBad = try image(width: 5, height: 8) { _, _ in [0, 0, 0, 255] }
        let horizontalBad = try image(width: 4, height: 7) { _, _ in [0, 0, 0, 255] }
        do { _ = try ImageProcessing.stitch(images: [a, verticalBad], direction: .vertical); throw TestFailure(message: "vertical width mismatch was accepted", file: #filePath, line: #line) }
        catch ImageProcessingError.incompatibleDimensions { }
        do { _ = try ImageProcessing.stitch(images: [a, horizontalBad], direction: .horizontal); throw TestFailure(message: "horizontal height mismatch was accepted", file: #filePath, line: #line) }
        catch ImageProcessingError.incompatibleDimensions { }
    }

    static func testRendererCompositesAnnotationsIntoActualPixelImage() throws {
        let source = try image(width: 30, height: 30) { _, _ in [20, 30, 40, 255] }
        let mark = EditorMark(tool: .rectangle, points: [CGPoint(x: 4, y: 4), CGPoint(x: 25, y: 25)], color: .red, width: 3)
        let output = ImageEditorRenderer.render(image: source, marks: [mark])
        let cg = try require(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cg.width == 30 && cg.height == 30, "rendered dimensions")
        try check(pixel(cg, x: 4, y: 15)[0] == 255, "rendered rectangle edge")
        try check(pixel(cg, x: 15, y: 15) == [20, 30, 40, 255], "rendered rectangle leaves interior intact")
    }

    static func testMosaicIsMaskedToTheSelectedPixels() throws {
        let source = try image(width: 40, height: 24) { x, y in
            let v: UInt8 = (x + y).isMultiple(of: 2) ? 0 : 255
            return [v, v, v, 255]
        }
        let mark = EditorMark(tool: .mosaic, points: [CGPoint(x: 8, y: 6), CGPoint(x: 30, y: 18)], color: .red, width: 4)
        let output = ImageEditorRenderer.render(image: source, marks: [mark])
        let originalCG = try require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let outputCG = try require(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let noMarks = try require(ImageEditorRenderer.render(image: source, marks: []).cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(noMarks, x: 2, y: 2) == pixel(originalCG, x: 2, y: 2), "renderer preserves source orientation and pixels")
        try check(pixel(outputCG, x: 2, y: 2) == pixel(originalCG, x: 2, y: 2), "mosaic preserves pixels outside its rectangle")
        try check(pixel(outputCG, x: 12, y: 10) != pixel(originalCG, x: 12, y: 10), "mosaic changes pixels inside its rectangle")
    }

    static func testCanvasUndoRedoRestoresCompositePixels() throws {
        let source = try image(width: 30, height: 30) { _, _ in [20, 30, 40, 255] }
        let view = EditorCanvasView(image: source)
        view.addAnnotation(EditorMark(tool: .rectangle, points: [CGPoint(x: 4, y: 4), CGPoint(x: 25, y: 25)], color: .red, width: 3))
        let annotated = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(annotated, x: 4, y: 15)[0] == 255, "annotation is present before undo")
        view.undoLastEdit()
        let undone = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(undone, x: 4, y: 15) == [20, 30, 40, 255], "undo restores source pixels")
        view.redoLastEdit()
        let redone = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(redone, x: 4, y: 15)[0] == 255, "redo restores annotation pixels")
    }

    static func testCropUndoRedoRestoresSourceAndAnnotations() throws {
        let source = try image(width: 10, height: 8) { x, y in [UInt8(x * 20), UInt8(y * 20), 10, 255] }
        let view = EditorCanvasView(image: source)
        view.addAnnotation(EditorMark(tool: .rectangle, points: [CGPoint(x: 2, y: 2), CGPoint(x: 8, y: 6)], color: .red, width: 2))
        let beforeCrop = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check((0..<beforeCrop.height).contains { y in (0..<beforeCrop.width).contains { x in let p = pixel(beforeCrop, x: x, y: y); return p[0] > 200 && p[1] < 80 } }, "annotation exists before crop")
        try view.cropImage(to: CGRect(x: 1, y: 1, width: 6, height: 5))
        let cropped = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(cropped.width == 6 && cropped.height == 5, "crop updates canvas dimensions")
        view.undoLastEdit()
        let undone = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(undone.width == 10 && undone.height == 8, "crop undo restores original dimensions")
        try check((0..<undone.height).contains { y in (0..<undone.width).contains { x in let p = pixel(undone, x: x, y: y); return p[0] > 200 && p[1] < 80 } }, "crop undo restores earlier annotations")
        view.redoLastEdit()
        let redone = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(redone.width == 6 && redone.height == 5, "crop redo restores cropped dimensions")
    }

    static func testHEICImageIOEncoding() throws {
        let source = try image(width: 12, height: 8) { x, y in [UInt8(x * 10), UInt8(y * 15), 60, 255] }
        let cg = try require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = NSMutableData()
        let destination = try require(CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        try check(CGImageDestinationFinalize(destination), "HEIC encoding completes")
        let sourceRef = try require(CGImageSourceCreateWithData(data, nil))
        let decoded = try require(CGImageSourceCreateImageAtIndex(sourceRef, 0, nil))
        try check(decoded.width == 12 && decoded.height == 8, "HEIC keeps pixel dimensions")
    }

    static func testQAFixtureOrientationAndWriteEvidence() throws {
        let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/qa-fixture.png")
        let fixture = try require(NSImage(contentsOf: fixtureURL))
        let sourceCG = try require(fixture.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let topRed = pixel(sourceCG, x: 100, y: 300)
        let lowerBlue = pixel(sourceCG, x: 100, y: 540)
        try check(topRed[0] > 200 && topRed[1] < 100 && topRed[2] < 100, "QA fixture has red block in its top half: \(topRed)")
        try check(lowerBlue[2] > 200 && lowerBlue[0] < 100, "QA fixture has blue block below the red block: \(lowerBlue)")

        let topLabel = EditorMark(tool: .text, points: [CGPoint(x: 50, y: 40)], color: .black, width: 4, text: "TOP")
        let numberLabel = EditorMark(tool: .number, points: [CGPoint(x: 830, y: 40)], color: .systemOrange, width: 4, text: "7")
        let rendered = ImageEditorRenderer.render(image: fixture, marks: [topLabel, numberLabel])
        let renderedCG = try require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let renderedTop = pixel(renderedCG, x: 100, y: 300)
        let renderedLower = pixel(renderedCG, x: 100, y: 540)
        try check(renderedTop[0] > 200 && renderedTop[1] < 100 && renderedTop[2] < 100, "renderer keeps the red block in the upper half: \(renderedTop)")
        try check(renderedLower[2] > 200 && renderedLower[0] < 100, "renderer keeps the blue block below it: \(renderedLower)")
        try check(pixel(renderedCG, x: 831, y: 41)[0] > 150, "number mark is rendered at its requested upper location")

        _ = NSApplication.shared
        let canvas = EditorCanvasView(image: fixture, marks: [topLabel, numberLabel])
        canvas.zoomToFit = false
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [], backing: .buffered, defer: false)
        window.contentView = canvas
        let previewBitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4000, bitsPerPixel: 32))
        canvas.cacheDisplay(in: canvas.bounds, to: previewBitmap)
        let previewCG = try require(previewBitmap.cgImage)
        let previewTop = pixel(previewCG, x: 100, y: 300)
        let previewLower = pixel(previewCG, x: 100, y: 540)
        try check(previewTop[0] > 200 && previewTop[1] < 100 && previewTop[2] < 100, "canvas preview shows upper red above lower blue")
        try check(previewLower[2] > 200 && previewLower[0] < 100, "canvas preview keeps blue in the lower half")
        try check(pixel(previewCG, x: 831, y: 41)[0] > 150, "canvas preview places the number in the upper half")
        window.contentView = nil

        let upperCrop = try ImageProcessing.crop(image: fixture, rect: CGRect(x: 0, y: 0, width: 320, height: 420))
        let cropCG = try require(upperCrop.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cropRed = pixel(cropCG, x: 100, y: 300)
        try check(cropRed[0] > 200 && cropRed[1] < 100, "top crop contains the upper red block, not lower blue pixels")

        let first = try ImageProcessing.crop(image: fixture, rect: CGRect(x: 0, y: 0, width: 320, height: 400))
        let second = try ImageProcessing.crop(image: fixture, rect: CGRect(x: 0, y: 300, width: 320, height: 400))
        let stitched = try ImageProcessing.stitch(images: [first, second], direction: .vertical)
        let stitchedCG = try require(stitched.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(stitchedCG.height == 700, "stitched raster retains source row order and deduplicates 100px overlap (height \(stitchedCG.height))")
        let stitchedTop = pixel(stitchedCG, x: 100, y: 300), stitchedLower = pixel(stitchedCG, x: 100, y: 540)
        try check(stitchedTop[0] > 200 && stitchedTop[1] < 100 && stitchedTop[2] < 100 && stitchedLower[2] > 200 && stitchedLower[0] < 100, "stitch output keeps top red above lower blue: \(stitchedTop), \(stitchedLower)")

        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence", isDirectory: true)
        let preview = NSImage(size: NSSize(width: 1000, height: 700))
        preview.addRepresentation(previewBitmap)
        try writePNG(preview, to: evidence.appendingPathComponent("qa-render-orientation.png"))
        try writePNG(upperCrop, to: evidence.appendingPathComponent("qa-crop-orientation.png"))
        try writePNG(stitched, to: evidence.appendingPathComponent("qa-stitch-orientation.png"))
    }

    static func testEffectsReadTopLeftSourceCoordinates() throws {
        let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/qa-fixture.png")
        let fixture = try require(NSImage(contentsOf: fixtureURL))
        let source = try require(fixture.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let topSample = pixel(source, x: 100, y: 150)
        try check(topSample[0] > 240 && topSample[1] > 240 && topSample[2] > 240, "effect fixture sample is white in the upper area")
        for tool in [ImageEditorTool.mosaic, .blur] {
            let effected = ImageEditorRenderer.render(image: fixture, marks: [EditorMark(tool: tool, points: [CGPoint(x: 50, y: 50), CGPoint(x: 270, y: 200)], color: .red, width: 8)])
            let result = pixel(try require(effected.cgImage(forProposedRect: nil, context: nil, hints: nil)), x: 100, y: 150)
            try check(result[2] > 180 && result[0] > 180 && result[1] > 180, "\(tool.rawValue) reads upper source pixels instead of lower blue rows: \(result)")
        }
        let magnified = ImageEditorRenderer.render(image: fixture, marks: [EditorMark(tool: .magnifier, points: [CGPoint(x: 700, y: 50), CGPoint(x: 800, y: 150)], color: .red, width: 3)])
        let magnifiedPixel = pixel(try require(magnified.cgImage(forProposedRect: nil, context: nil, hints: nil)), x: 750, y: 100)
        try check(magnifiedPixel[0] > 230 && magnifiedPixel[1] > 230 && magnifiedPixel[2] > 230, "magnifier samples the upper source region: \(magnifiedPixel)")
    }

    static func testDocumentRoundTripAndNewUndoHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("screenshotking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = try image(width: 20, height: 12) { x, y in [UInt8((x + y).isMultiple(of: 2) ? 0 : 255), 60, 100, 255] }
        let editor = EditorCanvasView(image: source)
        let marks = [
            EditorMark(tool: .mosaic, points: [CGPoint(x: 2, y: 2), CGPoint(x: 14, y: 8)], color: .orange, width: 5),
            EditorMark(tool: .note, points: [CGPoint(x: 1, y: 1)], color: .red, width: 2, text: "note"),
            EditorMark(tool: .sticker, points: [CGPoint(x: 6, y: 1)], color: .orange, width: 4, text: "⭐️"),
            EditorMark(tool: .magnifier, points: [CGPoint(x: 8, y: 4), CGPoint(x: 18, y: 10)], color: .blue, width: 2),
            EditorMark(tool: .watermark, points: [CGPoint(x: 1, y: 10)], color: .black, width: 3, text: "LOCAL"),
            EditorMark(tool: .step, points: [CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 3)], color: .red, width: 2, text: "Review result", stepNumber: 3, style: AnnotationStyle(step: .connected))
        ]
        for mark in marks { editor.addAnnotation(mark) }
        for url in [folder.appendingPathComponent("resume.skedit"), folder.appendingPathComponent("resume.json")] {
            let style = ImageEditorExportStyle(cornerRadius: 11, shadow: true, scaleToOneX: true)
            try ImageEditorDocument.save(to: url, sourceImage: source, workingImage: editor.imageForDocument, marks: editor.annotationsForDocument, style: style)
            let restored = try ImageEditorDocument.load(from: url)
            try check(restored.marks.count == 6 && restored.marks.map(\.tool) == marks.map(\.tool), "document restores effect and local marks at \(url.pathExtension)")
            try check(restored.marks[5].stepNumber == 3 && restored.marks[5].text == "Review result" && restored.marks[5].style.step == .connected, "document round-trips the step number, description and layout style")
            try check(restored.style == style, "document restores export style at \(url.pathExtension)")
            let reopened = EditorCanvasView(image: restored.workingImage, marks: restored.marks)
            reopened.addAnnotation(EditorMark(tool: .note, points: [CGPoint(x: 1, y: 1)], color: .blue, width: 2, text: "continue"))
            reopened.undoLastEdit()
            try check(reopened.annotationsForDocument.count == 6 && reopened.annotationsForDocument[0].tool == .mosaic, "reopened editor has a fresh undo history")
            let decoded = try require(reopened.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
            try check(decoded.width == 20 && decoded.height == 12, "reopened source dimensions are retained")
        }
        let legacyURL = folder.appendingPathComponent("legacy.json")
        try ImageEditorDocument.save(to: legacyURL, sourceImage: source, workingImage: source, marks: [EditorMark(tool: .step, points: [CGPoint(x: 2, y: 2)], color: .red, width: 2, text: "7")])
        var legacy = try require(JSONSerialization.jsonObject(with: Data(contentsOf: legacyURL)) as? [String: Any])
        var legacyMarks = try require(legacy["marks"] as? [[String: Any]])
        legacyMarks[0].removeValue(forKey: "stepNumber")
        legacyMarks[0]["text"] = "7"
        legacy["marks"] = legacyMarks
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyURL)
        let migrated = try ImageEditorDocument.load(from: legacyURL).marks[0]
        try check(migrated.stepNumber == 7 && migrated.text.isEmpty, "legacy numeric step text migrates to a sequence field and empty editable description")
        let damaged = folder.appendingPathComponent("damaged.json")
        try Data("not a document".utf8).write(to: damaged)
        do { _ = try ImageEditorDocument.load(from: damaged); throw TestFailure(message: "damaged edit document was accepted", file: #filePath, line: #line) }
        catch is DecodingError { }
        try FileManager.default.removeItem(at: folder)
    }

    static func testNumberMouseDownMouseUpDoesNotCrash() throws {
        _ = NSApplication.shared
        let source = try image(width: 12, height: 10) { _, _ in [40, 50, 60, 255] }
        let view = EditorCanvasView(image: source)
        view.frame = NSRect(x: 0, y: 0, width: 12, height: 10)
        view.tool = .number
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 12, height: 10), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 4, y: 4), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 4, y: 4), modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw TestFailure(message: "could not create mouse event fixtures", file: #filePath, line: #line)
        }
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        try check(view.annotationsForDocument.count == 1 && view.annotationsForDocument[0].tool == .number, "number tool handles its follow-up mouseUp safely")
        window.contentView = nil
    }

    static func testThemeResolvesExistingAnnotations() throws {
        let defaults = UserDefaults.standard
        let oldColor = defaults.object(forKey:"annotationThemeColor"),oldSize = defaults.object(forKey:"annotationThemeSize")
        defer {
            if let oldColor { defaults.set(oldColor,forKey:"annotationThemeColor") } else { defaults.removeObject(forKey:"annotationThemeColor") }
            if let oldSize { defaults.set(oldSize,forKey:"annotationThemeSize") } else { defaults.removeObject(forKey:"annotationThemeSize") }
        }
        let source = try image(width:96,height:48) { _,_ in [255,255,255,255] }
        var style = AnnotationStyle(colorPreset:.theme);style.followsThemeSize = true
        let mark = EditorMark(tool:.arrow,points:[CGPoint(x:10,y:24),CGPoint(x:80,y:24)],color:.green,width:4,style:style)
        AnnotationTheme.color = .red
        let red = try require(ImageEditorRenderer.render(image:source,marks:[mark]).cgImage(forProposedRect:nil,context:nil,hints:nil))
        AnnotationTheme.color = .blue
        let blue = try require(ImageEditorRenderer.render(image:source,marks:[mark]).cgImage(forProposedRect:nil,context:nil,hints:nil))
        try check(pixel(red,x:40,y:24)[0] > 200 && pixel(blue,x:40,y:24)[2] > 200 && pixel(blue,x:40,y:24)[0] < 50,"existing theme-linked mark changes with global theme color")
        AnnotationTheme.size = .large
        try check(style.resolvedFontSize == 23,"theme-linked font resolves current global size")
        var shapeStyle = AnnotationStyle(fontSize:24);shapeStyle.followsThemeSize = true
        try check(abs(shapeStyle.resolvedFontSize - 24 * 23 / 17) < 0.001,"theme font scaling preserves a shape's 24pt base size")
        let restored = try JSONDecoder().decode(AnnotationStyle.self,from:JSONEncoder().encode(style))
        try check(restored.followsThemeSize && restored.resolvedFontSize == 23,"theme linkage survives document serialization")
    }

    static func testAnnotationStyleMigrationAndRoundTrip() throws {
        let oldStyleData = Data("{\"fontName\":\"Helvetica\",\"fontSize\":17}".utf8)
        let oldStyle = try JSONDecoder().decode(AnnotationStyle.self, from: oldStyleData)
        try check(oldStyle.bold == false && oldStyle.mosaicStyle == .pixelated && oldStyle.magnifierScale == 2, "old style JSON receives documented defaults")
        var style = AnnotationStyle(shape: .chatBubble, fill: .hatched, arrow: .dashedDouble, brush: .highlighter, step: .connected, stepDirection: .left, highlightOpacity: 0.55, mosaicMode: .brushLarge, mosaicStyle: .strongBlur, magnifierScale: 3.5, watermarkOpacity: 0.42, watermarkDensity: 1.4, watermarkAngle: -14, bold: true, italic: true, underline: true, strikethrough: true)
        style.textBackground = AnnotationRGBA(NSColor.white.withAlphaComponent(0.8))
        let data = try JSONEncoder().encode(style)
        let restored = try JSONDecoder().decode(AnnotationStyle.self, from: data)
        try check(restored == style, "all per-mark style controls round-trip through Codable")
    }

    static func testShapeArrowBrushAndWatermarkPixels() throws {
        let source = try image(width: 512, height: 384) { _, _ in [255, 255, 255, 255] }
        for shape in AnnotationShape.allCases {
            for fill in AnnotationFill.allCases {
                let style = AnnotationStyle(shape: shape, fill: fill, fillColor: AnnotationRGBA(NSColor.systemBlue))
                let mark = EditorMark(tool: .shape, points: [CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 75)], color: .systemRed, width: 3, text: "S", style: style)
                let result = try require(ImageEditorRenderer.render(image: source, marks: [mark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
                let rep = NSBitmapImageRep(cgImage: result)
                let hasMark = (20..<90).contains { x in (20..<75).contains { y in
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return c.redComponent < 0.96 || c.greenComponent < 0.96 || c.blueComponent < 0.96
                } }
                try check(hasMark, "shape \(shape) with fill \(fill) paints pixels")
            }
        }
        for arrow in AnnotationArrow.allCases {
            let mark = EditorMark(tool: .arrow, points: [CGPoint(x: 15, y: 48), CGPoint(x: 110, y: 48)], color: .systemRed, width: 4, style: AnnotationStyle(arrow: arrow))
            let result = try require(ImageEditorRenderer.render(image: source, marks: [mark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
            try check(pixel(result, x: 50, y: 48)[0] > 180 && pixel(result, x: 50, y: 48)[1] < 150, "arrow style \(arrow) renders its line")
        }
        let outlinedArrow = EditorMark(tool: .arrow, points: [CGPoint(x: 25, y: 120), CGPoint(x: 130, y: 120)], color: .systemRed, width: 4, style: AnnotationStyle(arrow: .dashedSingle, textOutline: AnnotationRGBA(.systemBlue)))
        let outlinedArrowCG = try require(ImageEditorRenderer.render(image: source, marks: [outlinedArrow]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(outlinedArrowCG, x: 48, y: 115)[2] > 150, "arrow custom outline color paints around its dashed stroke")
        try check(pixel(outlinedArrowCG, x: 45, y: 120)[0] > 150, "arrow keeps its own solid foreground over the outline")
        for brush in AnnotationBrush.allCases {
            let mark = EditorMark(tool: .pen, points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 80)], color: .systemGreen, width: 8, style: AnnotationStyle(brush: brush))
            let result = try require(ImageEditorRenderer.render(image: source, marks: [mark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let sample = pixel(result, x: 60, y: 45)
            try check(sample[1] > sample[0], "brush style \(brush) visibly paints the stroke")
        }
        let outlinedPen = EditorMark(tool: .pen, points: [CGPoint(x: 20, y: 150), CGPoint(x: 110, y: 210)], color: .systemGreen, width: 5, style: AnnotationStyle(brush: .pen, textOutline: AnnotationRGBA(.systemBlue)))
        let outlinedPenCG = try require(ImageEditorRenderer.render(image: source, marks: [outlinedPen]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let penOutlineRep = NSBitmapImageRep(cgImage: outlinedPenCG)
        let penOutlinePixels = (0..<512).reduce(0) { count, x in count + (0..<384).filter { y in
            let c = penOutlineRep.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
            return c.blueComponent > c.redComponent + 0.2 && c.blueComponent > c.greenComponent + 0.05
        }.count }
        try check(penOutlinePixels > 100, "pen outline uses the selected custom blue color")
        let watermarkStyle = AnnotationStyle(watermarkOpacity: 0.4, watermarkDensity: 1, watermarkAngle: -14)
        let watermark = EditorMark(tool: .watermark, points: [CGPoint(x: 0, y: 0)], color: .black, width: 2, text: "LOCAL", style: watermarkStyle)
        let tiled = try require(ImageEditorRenderer.render(image: source, marks: [watermark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let tiledRep = NSBitmapImageRep(cgImage: tiled)
        let changed = (0..<512).reduce(0) { count, x in count + ((0..<384).contains { y in tiledRep.colorAt(x: x, y: y)!.redComponent < 0.96 } ? 1 : 0) }
        try check(changed > 100, "watermark text repeats across the full image (changed columns: \(changed))")
        let hidden = try require(ImageEditorRenderer.render(image: source, marks: [EditorMark(tool: .watermark, points: [CGPoint.zero], color: .black, width: 2, text: "LOCAL", style: AnnotationStyle(watermarkVisible: false))]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(pixel(hidden, x: 60, y: 45) == [255, 255, 255, 255], "watermark visibility toggle suppresses text")
        let plainWatermark = EditorMark(tool: .watermark, points: [.zero], color: .black, width: 2, text: "Format", style: AnnotationStyle(watermarkOpacity: 0.9, watermarkDensity: 3, watermarkAngle: 0))
        var formattedStyle = plainWatermark.style;formattedStyle.underline = true;formattedStyle.strikethrough = true
        let formattedWatermark = EditorMark(tool: .watermark, points: [.zero], color: .black, width: 2, text: "Format", style: formattedStyle)
        let plainCG = try require(ImageEditorRenderer.render(image: source, marks: [plainWatermark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let formattedCG = try require(ImageEditorRenderer.render(image: source, marks: [formattedWatermark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let plainRep = NSBitmapImageRep(cgImage:plainCG),formattedRep = NSBitmapImageRep(cgImage:formattedCG)
        let formattingDifferences = (0..<100).reduce(0) { count, x in count + (0..<70).filter { y in plainRep.colorAt(x:x,y:y) != formattedRep.colorAt(x:x,y:y) }.count }
        try check(formattingDifferences > 20, "watermark keeps underline and strikethrough text formatting")
    }

    static func testSelectDragCopyDeleteUndoAndInlineText() throws {
        _ = NSApplication.shared
        let source = try image(width: 64, height: 48) { _, _ in [50, 60, 70, 255] }
        let view = EditorCanvasView(image: source)
        view.frame = NSRect(x: 0, y: 0, width: 64, height: 48); view.zoomToFit = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 48), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view
        view.addAnnotation(EditorMark(tool: .rectangle, points: [CGPoint(x: 8, y: 8), CGPoint(x: 24, y: 24)], color: .systemRed, width: 3))
        view.tool = .select
        let down = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 14, y: 34), modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1))
        let drag = try require(NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: 20, y: 30), modifierFlags: [], timestamp: 2.1, windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: 1, pressure: 1))
        let up = try require(NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 20, y: 30), modifierFlags: [], timestamp: 2.2, windowNumber: window.windowNumber, context: nil, eventNumber: 5, clickCount: 1, pressure: 0))
        view.mouseDown(with: down); view.mouseDragged(with: drag); view.mouseUp(with: up)
        try check(view.annotationsForDocument[0].points[0] == CGPoint(x: 14, y: 12), "selection dragging moves existing geometry (actual: \(view.annotationsForDocument[0].points[0]), selected: \(String(describing: view.selectedMarkIndex)))")
        view.undoLastEdit()
        try check(view.annotationsForDocument[0].points[0] == CGPoint(x: 8, y: 8), "undo restores moved geometry")
        view.copySelectedMark(); view.pasteCopiedMark()
        try check(view.annotationsForDocument.count == 2, "copy and paste duplicates the selected mark")
        view.deleteSelectedMark()
        try check(view.annotationsForDocument.count == 1, "delete removes the selected mark")
        view.undoLastEdit()
        try check(view.annotationsForDocument.count == 2, "undo restores deleted annotations")
        let textView = EditorCanvasView(image: source); textView.frame = NSRect(x: 0, y: 0, width: 64, height: 48); textView.zoomToFit = false; textView.tool = .note
        let textWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 48), styleMask: [], backing: .buffered, defer: false); textWindow.contentView = textView
        let noteDown = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 35, y: 40), modifierFlags: [], timestamp: 3, windowNumber: textWindow.windowNumber, context: nil, eventNumber: 6, clickCount: 1, pressure: 1))
        let noteDoubleDown = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 35, y: 40), modifierFlags: [], timestamp: 3.1, windowNumber: textWindow.windowNumber, context: nil, eventNumber: 7, clickCount: 2, pressure: 1))
        textView.mouseDown(with: noteDown)
        textView.mouseDown(with: noteDoubleDown)
        try check(textView.subviews.compactMap({ $0 as? NSTextField }).count == 1, "single then double mouse-down reuses one inline note field")
        guard let editor = textView.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "inline note editor did not open", file: #filePath, line: #line) }
        editor.stringValue = "inline note"
        _ = textView.control(editor, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        textView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: editor))
        try check(textView.subviews.compactMap({ $0 as? NSTextField }).isEmpty, "committed inline editor is removed once")
        try check(textView.annotationsForDocument.contains(where: { $0.tool == .note && $0.text == "inline note" }), "note text is entered inline and committed as an undoable mark")
        try check(textView.annotationsForDocument.filter({ $0.tool == .note }).count == 1, "repeated click and text end notifications submit only one note")
        textView.undoLastEdit()
        try check(!textView.annotationsForDocument.contains(where: { $0.tool == .note }), "undo reverts inline text creation")
        textView.mouseDown(with: noteDown)
        guard let cancelledEditor = textView.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "second inline note editor did not open", file: #filePath, line: #line) }
        cancelledEditor.stringValue = "cancel me"
        _ = textView.control(cancelledEditor, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        try check(textView.annotationsForDocument.filter({ $0.tool == .note }).isEmpty && textView.subviews.compactMap({ $0 as? NSTextField }).isEmpty, "Escape cancels the active inline draft")
        try check(textView.acceptsFirstResponder && textWindow.makeFirstResponder(textView),"canvas accepts actual AppKit keyboard focus")
        textView.mouseDown(with:noteDown)
        let pending = try require(textView.subviews.compactMap { $0 as? NSTextField }.first)
        pending.stringValue = "save pending note"
        _ = textView.renderedImage(cornerRadius:0,shadow:false,scaleToOneX:false)
        try check(textView.annotationsForDocument.contains { $0.text == "save pending note" } && textView.subviews.compactMap({$0 as? NSTextField}).isEmpty,"export action commits active text before rendering")
        textWindow.contentView = nil

        let stepSource = try image(width: 240, height: 120) { _, _ in [50, 60, 70, 255] }
        let stepView = EditorCanvasView(image: stepSource); stepView.frame = NSRect(x: 0, y: 0, width: 240, height: 120); stepView.zoomToFit = false; stepView.tool = .step
        let stepWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120), styleMask: [], backing: .buffered, defer: false); stepWindow.contentView = stepView
        func stepEvent(_ type: NSEvent.EventType, imagePoint: CGPoint, clickCount: Int = 1, eventNumber: Int) throws -> NSEvent {
            try require(NSEvent.mouseEvent(with: type, location: CGPoint(x: imagePoint.x, y: 120 - imagePoint.y), modifierFlags: [], timestamp: Double(eventNumber), windowNumber: stepWindow.windowNumber, context: nil, eventNumber: eventNumber, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1))
        }
        stepView.mouseDown(with: try stepEvent(.leftMouseDown, imagePoint: CGPoint(x: 8, y: 10), eventNumber: 20))
        stepView.mouseUp(with: try stepEvent(.leftMouseUp, imagePoint: CGPoint(x: 8, y: 10), eventNumber: 21))
        guard let stepEditor = stepView.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "step creation did not open inline description editor", file: #filePath, line: #line) }
        stepEditor.stringValue = "Choose region"
        stepView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: stepEditor))
        try check(stepView.annotationsForDocument.last?.stepNumber == 1 && stepView.annotationsForDocument.last?.text == "Choose region", "step stores its sequence number separately from the editable description")
        let oldBubblePoint = stepView.annotationsForDocument[0].points[1]
        stepView.mouseDown(with: try stepEvent(.leftMouseDown, imagePoint: oldBubblePoint, clickCount: 2, eventNumber: 22))
        guard let editStep = stepView.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "double-click did not edit step description", file: #filePath, line: #line) }
        editStep.stringValue = "Select the region"
        stepView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: editStep))
        try check(stepView.annotationsForDocument[0].text == "Select the region", "double-click edits an existing step description")
        stepView.tool = .select
        stepView.mouseDown(with: try stepEvent(.leftMouseDown, imagePoint: CGPoint(x: 18, y: 20), eventNumber: 23))
        stepView.mouseDragged(with: try stepEvent(.leftMouseDragged, imagePoint: CGPoint(x: 24, y: 26), eventNumber: 24))
        stepView.mouseUp(with: try stepEvent(.leftMouseUp, imagePoint: CGPoint(x: 24, y: 26), eventNumber: 25))
        try check(stepView.annotationsForDocument[0].points[0] == CGPoint(x: 14, y: 16) && stepView.annotationsForDocument[0].points[1] == CGPoint(x: oldBubblePoint.x + 6, y: oldBubblePoint.y + 6), "drag moves both step anchor and callout body")
        stepView.undoLastEdit()
        try check(stepView.annotationsForDocument[0].points[0] == CGPoint(x: 8, y: 10) && stepView.annotationsForDocument[0].text == "Select the region", "undo restores the complete step callout")
        stepView.copySelectedMark(); stepView.pasteCopiedMark()
        try check(stepView.annotationsForDocument.count == 2 && stepView.annotationsForDocument[1].stepNumber == 1 && stepView.annotationsForDocument[1].text == "Select the region", "copy preserves step number and description")
        stepView.deleteSelectedMark(); stepView.undoLastEdit()
        try check(stepView.annotationsForDocument.count == 2, "delete and undo restore a step callout")
        stepWindow.contentView = nil
        window.contentView = nil
    }

    static func testStepDistinctionStickerPNGAndEvidenceSheet() throws {
        let source = try image(width: 512, height: 384) { _, _ in [245, 245, 245, 255] }
        let integrated = EditorMark(tool: .step, points: [CGPoint(x: 120, y: 90), CGPoint(x: 162, y: 90)], color: .systemRed, width: 4, text: "选择区域", stepNumber: 1, style: AnnotationStyle(step: .integrated, fontSize: 17))
        let connected = EditorMark(tool: .step, points: [CGPoint(x: 250, y: 110), CGPoint(x: 180, y: 170)], color: .systemBlue, width: 4, text: "添加标注", stepNumber: 2, style: AnnotationStyle(step: .connected, fontSize: 17))
        let integratedImage = try require(ImageEditorRenderer.render(image: source, marks: [integrated]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let connectedImage = try require(ImageEditorRenderer.render(image: source, marks: [connected]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let integratedRep = NSBitmapImageRep(cgImage: integratedImage), connectedRep = NSBitmapImageRep(cgImage: connectedImage)
        var differences = 0
        for y in 90..<210 { for x in 120..<360 {
            let a = integratedRep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let b = connectedRep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if abs(a.redComponent - b.redComponent) > 0.1 || abs(a.greenComponent - b.greenComponent) > 0.1 || abs(a.blueComponent - b.blueComponent) > 0.1 { differences += 1 }
        }}
        try check(differences > 400, "integrated and leader-connected callouts with separate descriptions render differently")
        try check(integrated.text == "选择区域" && integrated.stepNumber == 1 && connected.text == "添加标注" && connected.stepNumber == 2, "step descriptions and sequence fields remain independent")
        try check(pixel(integratedImage, x: 200, y: 100)[3] > 0 && pixel(connectedImage, x: 220, y: 180)[3] > 0, "both step callouts render visible bubble and text pixels")
        for labelPoint in [CGPoint(x: 100, y: 140), CGPoint(x: 250, y: 65), CGPoint(x: 250, y: 230)] {
            let flexible = EditorMark(tool: .step, points: [CGPoint(x: 250, y: 150), labelPoint], color: .systemRed, width: 4, text: "Move body", stepNumber: 3, style: AnnotationStyle(step: .integrated))
            let image = try require(ImageEditorRenderer.render(image: source, marks: [flexible]).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let sample: CGPoint
            if labelPoint.x < 200 { sample = CGPoint(x: 230, y: 158) }
            else if labelPoint.y < 100 { sample = CGPoint(x: 259, y: 127) }
            else { sample = CGPoint(x: 259, y: 204) }
            let bridgePixel = pixel(image, x: Int(sample.x), y: Int(sample.y))
            try check(bridgePixel[0] > 100 && bridgePixel[1] < 160, "integrated outlined capsule bridge reaches moved callout at \(labelPoint): \(bridgePixel)")
        }

        let redPNG = try image(width: 12, height: 12) { _, _ in [255, 0, 0, 255] }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pngURL = folder.appendingPathComponent("sticker.png"); try writePNG(redPNG, to: pngURL)
        let payload = try Data(contentsOf: pngURL)
        let selection = StickerSelection(id: "fixture-red", title: "红色贴纸", text: nil, pngData: payload)
        let sticker = EditorMark(tool: .sticker, points: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 50)], color: .black, width: 4, style: AnnotationStyle(sticker: selection))
        let stickerCG = try require(ImageEditorRenderer.render(image: source, marks: [sticker]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let stickerPixel = pixel(stickerCG, x: 30, y: 30)
        try check(stickerPixel[0] > 200 && stickerPixel[1] < 80, "PNG sticker payload draws inside the editable mark bounds: \(stickerPixel)")
        let emoji = EditorMark(tool: .sticker, points: [CGPoint(x: 70, y: 70)], color: .systemRed, width: 4, text: "L", style: AnnotationStyle(stickerRotation: 0))
        var rotatedEmoji = emoji;rotatedEmoji.style.stickerRotation = 90
        let emoji0 = try require(ImageEditorRenderer.render(image: source, marks: [emoji]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let emoji90 = try require(ImageEditorRenderer.render(image: source, marks: [rotatedEmoji]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let emojiRep0 = NSBitmapImageRep(cgImage:emoji0),emojiRep90 = NSBitmapImageRep(cgImage:emoji90)
        let emojiDifferences = (40..<120).reduce(0) { count, x in count + (40..<120).filter { y in emojiRep0.colorAt(x:x,y:y) != emojiRep90.colorAt(x:x,y:y) }.count }
        try check(emojiDifferences > 40, "emoji sticker rotation changes its rendered glyph orientation")
        try FileManager.default.removeItem(at: folder)

        let canvas = try image(width: 1400, height: 1000) { _, _ in [250, 250, 250, 255] }
        var marks = [EditorMark(tool: .note, points: [CGPoint(x: 35, y: 35)], color: .systemRed, width: 2, text: "备注 · inline text", style: AnnotationStyle(fontSize: 17, bold: true)), integrated, connected]
        for (index, shape) in AnnotationShape.allCases.enumerated() {
            let x = CGFloat(35 + (index % 4) * 150), y = CGFloat(260 + (index / 4) * 140)
            marks.append(EditorMark(tool: .shape, points: [CGPoint(x: x, y: y), CGPoint(x: x + 88, y: y + 72)], color: .systemPurple, width: 3, text: shape.title, style: AnnotationStyle(shape: shape, fill: index.isMultiple(of: 2) ? .translucent : .hatched, fontSize: 12)))
        }
        for (index, arrow) in AnnotationArrow.allCases.enumerated() {
            let x = CGFloat(650 + (index % 3) * 190), y = CGFloat(220 + (index / 3) * 110)
            marks.append(EditorMark(tool: .arrow, points: [CGPoint(x: x, y: y), CGPoint(x: x + 120, y: y + 20)], color: .systemOrange, width: 4, text: arrow.title, style: AnnotationStyle(arrow: arrow)))
        }
        marks.append(EditorMark(tool: .watermark, points: [.zero], color: .black, width: 2, text: "LOCAL DEMO", style: AnnotationStyle(watermarkOpacity: 0.22, watermarkDensity: 1.5, watermarkAngle: -14)))
        marks.append(sticker)
        let sheet = ImageEditorRenderer.render(image: canvas, marks: marks)
        try writePNG(sheet, to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/qa-annotation-tools.png"))
    }

    static func testRectangularHighlightPixels() throws {
        let source = try image(width: 32, height: 24) { _, _ in [240, 240, 240, 255] }
        let mark = EditorMark(tool: .highlight, points: [CGPoint(x: 6, y: 5), CGPoint(x: 22, y: 17)], color: .systemYellow, width: 3, style: AnnotationStyle(highlightOpacity: 0.4))
        let rendered = try require(ImageEditorRenderer.render(image: source, marks: [mark]).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let inside = pixel(rendered, x: 12, y: 10), outside = pixel(rendered, x: 3, y: 3)
        try check(inside[0] > inside[1] && inside[1] < 240 && inside[2] < 180, "area highlight tints the selected interior using its color and opacity: \(inside)")
        try check(outside == [240, 240, 240, 255], "area highlight leaves pixels outside the selected rectangle unchanged: \(outside)")
    }

    static func testSpacePanShiftConstraintAndToolShortcuts() throws {
        _ = NSApplication.shared

        let suiteName = "ImageEditorShortcuts-\(UUID().uuidString)"
        let defaultsStore = try require(UserDefaults(suiteName: suiteName))
        defer { defaultsStore.removePersistentDomain(forName: suiteName) }
        var shortcuts = ImageEditorToolShortcuts.defaults
        shortcuts[ImageEditorTool.arrow.rawValue] = "x"
        ImageEditorToolShortcuts.save(shortcuts, to: defaultsStore)
        try check(ImageEditorToolShortcuts.load(from: defaultsStore)[ImageEditorTool.arrow.rawValue] == "x", "tool shortcut settings persist in the configured defaults store")

        let source = try image(width: 100, height: 80) { _, _ in [30, 40, 50, 255] }
        let view = EditorCanvasView(image: source, shortcutDefaults: defaultsStore)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 80); view.zoomToFit = false; view.tool = .arrow
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view
        func event(_ type: NSEvent.EventType, x: CGFloat, yTop: CGFloat, modifiers: NSEvent.ModifierFlags = [], number: Int) throws -> NSEvent {
            try require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 80 - yTop), modifierFlags: modifiers, timestamp: Double(number), windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }
        let spaceDown = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        let spaceUp = try require(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        view.keyDown(with: spaceDown)
        view.mouseDown(with: try event(.leftMouseDown, x: 40, yTop: 30, number: 1))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 55, yTop: 38, number: 2))
        view.mouseUp(with: try event(.leftMouseUp, x: 55, yTop: 38, number: 3))
        view.keyUp(with: spaceUp)
        view.mouseDown(with: try event(.leftMouseDown, x: 65, yTop: 48, number: 4))
        view.mouseUp(with: try event(.leftMouseUp, x: 65, yTop: 48, number: 5))
        let pannedArrow = try require(view.annotationsForDocument.first)
        try check(pannedArrow.points[0] == CGPoint(x: 50, y: 40), "space-drag pans the canvas and subsequent marks map back to image coordinates: \(pannedArrow.points)")

        let shortcutEvent = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 3, windowNumber: window.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
        view.tool = .select
        view.keyDown(with: shortcutEvent)
        try check(view.tool == .arrow, "configured single-key shortcut selects its tool (actual \(view.tool.rawValue), map \(ImageEditorToolShortcuts.load(from: defaultsStore)), chars \(String(describing: shortcutEvent.charactersIgnoringModifiers)), flags \(shortcutEvent.modifierFlags))")

        let squareView = EditorCanvasView(image: source, shortcutDefaults: defaultsStore)
        squareView.frame = NSRect(x: 0, y: 0, width: 100, height: 80); squareView.zoomToFit = false; squareView.tool = .shape
        let squareWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), styleMask: [], backing: .buffered, defer: false); squareWindow.contentView = squareView
        func shifted(_ type: NSEvent.EventType, x: CGFloat, yTop: CGFloat, number: Int) throws -> NSEvent {
            try require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 80 - yTop), modifierFlags: [.shift], timestamp: Double(number + 10), windowNumber: squareWindow.windowNumber, context: nil, eventNumber: number + 10, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }
        squareView.mouseDown(with: try shifted(.leftMouseDown, x: 20, yTop: 20, number: 1))
        squareView.mouseDragged(with: try shifted(.leftMouseDragged, x: 50, yTop: 35, number: 2))
        squareView.mouseUp(with: try shifted(.leftMouseUp, x: 50, yTop: 35, number: 3))
        let constrained = try require(squareView.annotationsForDocument.first)
        try check(constrained.points[1] == CGPoint(x: 50, y: 50), "Shift constrains shape drawing to a square: \(constrained.points)")

        let step = EditorMark(tool: .step, points: [CGPoint(x: 60, y: 30), CGPoint(x: 115, y: 30)], color: .systemRed, width: 3, text: "direction", stepNumber: 1, style: AnnotationStyle(step: .integrated, stepDirection: .right))
        squareView.addAnnotation(step)
        squareView.tool = .select
        squareView.mouseDown(with: try shifted(.leftMouseDown, x: 65, yTop: 35, number: 4))
        try check(squareView.selectedMarkIndex == 1, "existing step callout can be selected for direction changes")
        var leftStyle = step.style; leftStyle.stepDirection = .left
        squareView.updateSelectedStyle(leftStyle)
        try check(squareView.annotationsForDocument[1].points[1].x < squareView.annotationsForDocument[1].points[0].x, "changing step direction moves its callout body to the left of its anchor")
        squareView.undoLastEdit()
        try check(squareView.annotationsForDocument[1].points[1] == CGPoint(x: 115, y: 30) && squareView.annotationsForDocument[1].style.stepDirection == .right, "undo restores step direction and geometry together")
        let encoded = try JSONEncoder().encode(leftStyle)
        try check(try JSONDecoder().decode(AnnotationStyle.self, from: encoded).stepDirection == .left, "step direction persists through style serialization")
        window.contentView = nil; squareWindow.contentView = nil
    }

    static func testAccessibilityCanvasPressCreatesAndSavesText() throws {
        _ = NSApplication.shared
        let source = try image(width: 64, height: 48) { _, _ in [220, 225, 230, 255] }
        let view = EditorCanvasView(image: source)
        view.frame = NSRect(x: 0, y: 0, width: 64, height: 48); view.zoomToFit = false; view.tool = .note
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 48), styleMask: [], backing: .buffered, defer: false); window.contentView = view
        try check(view.accessibilityRole() == .button, "canvas exposes an actionable accessibility role")
        try check(try require(view.accessibilityLabel()).contains("按下可在画布中心创建并编辑"), "canvas accessibility label explains the active text creation action")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("screenshotking-ax-\(UUID().uuidString)", isDirectory: true)
        let documentURL = folder.appendingPathComponent("accessible.skedit")
        var saveError: Error?
        view.onDocumentChanged = { editedImage, marks in
            do { try ImageEditorDocument.save(to: documentURL, sourceImage: source, workingImage: editedImage, marks: marks) }
            catch { saveError = error }
        }
        let didPress = view.accessibilityPerformPress()
        try check(didPress, "AX press opens the same inline editor used by pointer input (tool=\(view.tool.rawValue), bounds=\(view.bounds), fields=\(view.subviews.compactMap { $0 as? NSTextField }.count))")
        guard let field = view.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "AX press did not create an inline text field", file: #filePath, line: #line) }
        try check(view.subviews.compactMap({ $0 as? NSTextField }).count == 1, "AX press creates one editable field")
        field.stringValue = "AX note saved"
        _ = view.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        try check(saveError == nil, "committed AX note autosaves without an error: \(String(describing: saveError))")
        let restored = try ImageEditorDocument.load(from: documentURL)
        try check(restored.marks.count == 1 && restored.marks[0].tool == .note && restored.marks[0].text == "AX note saved", "AX text entry is persisted and read back from the native edit document")
        try FileManager.default.removeItem(at: folder)
        window.contentView = nil
    }

    static func testHostedCanvasAXPressSavesNoteAndStep() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let oldDefault = UserDefaults.standard.object(forKey: "defaultEditorTool")
        UserDefaults.standard.set("Note", forKey: "defaultEditorTool")
        defer { if let oldDefault { UserDefaults.standard.set(oldDefault, forKey: "defaultEditorTool") } else { UserDefaults.standard.removeObject(forKey: "defaultEditorTool") } }
        let source = try image(width: 80, height: 60) { _, _ in [230, 230, 230, 255] }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("screenshotking-hosted-\(UUID().uuidString)", isDirectory: true)
        let documentURL = folder.appendingPathComponent("hosted.skedit")
        let root = ImageEditorContent(image: source, documentURL: documentURL, onPin: { _ in })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        func findCanvas(_ view: NSView) -> EditorCanvasView? {
            if let canvas = view as? EditorCanvasView { return canvas }
            for child in view.subviews { if let canvas = findCanvas(child) { return canvas } }
            return nil
        }
        guard let canvas = findCanvas(hosting) else { throw TestFailure(message: "NSHostingView did not mount the native editor canvas", file: #filePath, line: #line) }
        try check(canvas.tool == .note && canvas.window === window && !canvas.bounds.isEmpty, "hosted canvas is attached, sized, and in the note tool state")
        try check(canvas.accessibilityPerformPress(), "native hosted canvas accessibility press opens the inline editor")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "hosted canvas accessibility press did not leave a visible text field on the canvas", file: #filePath, line: #line) }
        try check(field.isBezeled && field.drawsBackground && field.placeholderString?.contains("输入备注") == true, "hosted inline text editor is visibly bordered and explains what to enter")
        try check(canvas.bounds.intersects(field.frame), "hosted inline field is placed within visible canvas bounds")
        canvas.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try check(canvas.subviews.contains(where: { $0 === field }), "an empty draft survives a real text-end notification and the following run loop")
        try check(canvas.accessibilityPerformPress(), "AX press can refocus an existing same-tool empty draft")
        field.stringValue = "Hosted toolbar note"
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        let restored = try ImageEditorDocument.load(from: documentURL)
        try check(restored.marks.count == 1 && restored.marks[0].text == "Hosted toolbar note", "hosted note input autosaves and reads back after the run loop")
        let rendered = try require(canvas.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let base = try require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var changedPixels = 0
        for y in 0..<rendered.height { for x in 0..<rendered.width where pixel(rendered, x: x, y: y) != pixel(base, x: x, y: y) { changedPixels += 1 } }
        try check(changedPixels > 10, "hosted canvas note appears in the composed export pixels (changed: \(changedPixels))")
        window.orderOut(nil);window.contentView = nil
        try FileManager.default.removeItem(at: folder)

        UserDefaults.standard.set("Step", forKey: "defaultEditorTool")
        let stepFolder = FileManager.default.temporaryDirectory.appendingPathComponent("screenshotking-hosted-step-\(UUID().uuidString)", isDirectory: true)
        let stepDocumentURL = stepFolder.appendingPathComponent("hosted-step.skedit")
        let stepRoot = ImageEditorContent(image: source, documentURL: stepDocumentURL, onPin: { _ in })
        let stepHosting = NSHostingView(rootView: stepRoot)
        stepHosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let stepWindow = NSWindow(contentRect: stepHosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        stepWindow.contentView = stepHosting
        stepWindow.makeKeyAndOrderFront(nil)
        stepHosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let stepCanvas = findCanvas(stepHosting) else { throw TestFailure(message: "NSHostingView did not mount the step canvas", file: #filePath, line: #line) }
        try check(stepCanvas.tool == .step && stepCanvas.accessibilityPerformPress(), "native hosted canvas accessibility press opens the step editor")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let stepField = stepCanvas.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "hosted Add Step action did not create its inline field", file: #filePath, line: #line) }
        try check(stepField.placeholderString?.contains("步骤说明") == true && stepCanvas.bounds.intersects(stepField.frame), "hosted step editor is visible and identifies the description field")
        stepField.stringValue = "Hosted step description"
        _ = stepCanvas.control(stepField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        let restoredStep = try ImageEditorDocument.load(from: stepDocumentURL)
        try check(restoredStep.marks.count == 1 && restoredStep.marks[0].tool == .step && restoredStep.marks[0].stepNumber == 1 && restoredStep.marks[0].text == "Hosted step description", "hosted step input saves and reads back its sequence number and description")
        let renderedStep = try require(stepCanvas.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let baseStep = try require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let renderedStepRep = NSBitmapImageRep(cgImage: renderedStep), baseStepRep = NSBitmapImageRep(cgImage: baseStep)
        var stepPixelsChanged = 0
        for y in 0..<renderedStep.height { for x in 0..<renderedStep.width {
            if renderedStepRep.colorAt(x: x, y: y) != baseStepRep.colorAt(x: x, y: y) { stepPixelsChanged += 1 }
        }}
        try check(stepPixelsChanged > 10, "hosted step description appears in the composed export pixels (changed: \(stepPixelsChanged))")

        stepCanvas.tool = .note
        try check(stepCanvas.accessibilityPerformPress(), "switching from a submitted step to note creates a fresh editor on the same hosted canvas")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let noteAfterStep = stepCanvas.subviews.compactMap({ $0 as? NSTextField }).first else { throw TestFailure(message: "note editor did not open after step submission in the same window", file: #filePath, line: #line) }
        noteAfterStep.stringValue = "Note after step"
        _ = stepCanvas.control(noteAfterStep, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        let afterStepDocument = try ImageEditorDocument.load(from: stepDocumentURL)
        try check(afterStepDocument.marks.count == 2 && afterStepDocument.marks[1].tool == .note && afterStepDocument.marks[1].text == "Note after step", "same-window step-to-note transition commits both marks to the document")
        stepWindow.orderOut(nil);stepWindow.contentView = nil
        try FileManager.default.removeItem(at: stepFolder)
    }

    static func testCanvasDragPreviewRendersEffectsOffscreen() throws {
        _ = NSApplication.shared
        let source = try image(width: 24, height: 18) { x, y in
            let light = (x + y).isMultiple(of: 2) ? UInt8(250) : UInt8(5)
            return [light, light, light, 255]
        }
        let view = EditorCanvasView(image: source)
        view.frame = NSRect(x: 0, y: 0, width: 24, height: 18)
        view.tool = .blur
        view.markWidth = 5
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 18), styleMask: [], backing: .buffered, defer: false)
        window.contentView = view
        let down = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 3, y: 3), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let drag = try require(NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: 20, y: 14), modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        view.mouseDragged(with: drag)
        let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 24 * 4, bitsPerPixel: 32))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let drawn = try require(bitmap.cgImage)
        let before = pixel(try require(source.cgImage(forProposedRect: nil, context: nil, hints: nil)), x: 12, y: 9)[0]
        let duringDrag = pixel(drawn, x: 12, y: 9)[0]
        try check(duringDrag != before, "blur preview is rendered during mouse drag through the bitmap compositor")
        window.contentView = nil
    }

    static func testFramingAndOneXExportAffectRealPixels() throws {
        let pixelImage = try image(width: 12, height: 8) { _, _ in [80, 120, 160, 255] }
        let cg = try require(pixelImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let retina = NSImage(cgImage: cg, size: NSSize(width: 6, height: 4))
        let rounded = ImageEditorRenderer.render(image: retina, marks: [], cornerRadius: 3, shadow: false, scaleToOneX: false)
        let roundedCG = try require(rounded.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(roundedCG.width == 12 && roundedCG.height == 8, "original-size export preserves pixels")
        try check(rounded.size == NSSize(width: 6, height: 4), "original-size export preserves Retina logical size")
        let cornerAlpha = pixel(roundedCG, x: 0, y: 0)[3]
        try check(cornerAlpha < 128, "rounded corners export with transparent pixels (alpha \(cornerAlpha))")
        try check(pixel(roundedCG, x: 6, y: 4)[3] == 255, "rounded image center stays opaque")
        let shadowed = ImageEditorRenderer.render(image: retina, marks: [], cornerRadius: 3, shadow: true, scaleToOneX: false)
        let shadowCG = try require(shadowed.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(shadowCG.width == 60 && shadowCG.height == 56, "shadow export reserves visible margin")
        try check(shadowed.size == NSSize(width: 30, height: 28), "shadow margin is expressed in logical points")
        let shadowPixelsOutsideImage = (0..<shadowCG.height).reduce(into: 0) { count, y in
            for x in 0..<shadowCG.width where !(24..<36).contains(x) || !(24..<32).contains(y) {
                if pixel(shadowCG, x: x, y: y)[3] > 0 { count += 1 }
            }
        }
        try check(shadowPixelsOutsideImage > 0, "shadow export includes visible pixels beyond the image bounds")
        let oneX = ImageEditorRenderer.render(image: retina, marks: [], cornerRadius: 3, shadow: true, scaleToOneX: true)
        let oneXCG = try require(oneX.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(oneXCG.width == 30 && oneXCG.height == 28, "1x export scales all output effects")
        try check(oneX.size == NSSize(width: 30, height: 28), "1x export uses pixel dimensions as logical size")
        try check(pixel(oneXCG, x: 0, y: 0)[3] == 0, "1x output keeps transparent rounded corners")
    }

    static func testRetinaAnnotationSizeAndExportPoints() throws {
        let oneX = try image(width: 80, height: 48) { _, _ in [255, 255, 255, 255] }
        let retinaPixels = try image(width: 160, height: 96) { _, _ in [255, 255, 255, 255] }
        let retina = NSImage(cgImage: try require(retinaPixels.cgImage(forProposedRect: nil, context: nil, hints: nil)), size: NSSize(width: 80, height: 48))
        let line1x = EditorMark(tool: .line, points: [CGPoint(x: 8, y: 24), CGPoint(x: 72, y: 24)], color: .black, width: 2)
        let line2x = EditorMark(tool: .line, points: [CGPoint(x: 16, y: 48), CGPoint(x: 144, y: 48)], color: .black, width: 2)
        let output1x = ImageEditorRenderer.render(image: oneX, marks: [line1x])
        let output2x = ImageEditorRenderer.render(image: retina, marks: [line2x])
        let cg1x = try require(output1x.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cg2x = try require(output2x.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(output1x.size == NSSize(width: 80, height: 48) && output2x.size == NSSize(width: 80, height: 48), "annotation export preserves 1x and Retina logical dimensions")
        func darkRows(_ cg: CGImage, x: Int, center: Int, radius: Int) -> Int {
            (max(0, center-radius)...min(cg.height-1, center+radius)).filter { pixel(cg, x: x, y: $0)[0] < 80 }.count
        }
        let line1Width = darkRows(cg1x, x: 40, center: 24, radius: 3)
        let line2Width = darkRows(cg2x, x: 80, center: 48, radius: 6)
        try check(line1Width >= 2 && line1Width <= 4, "1x line width matches 2 logical points: \(line1Width) px")
        try check(line2Width >= 4 && line2Width <= 8, "Retina line width scales to 2 logical points: \(line2Width) px")
        let oneXExport = ImageEditorRenderer.render(image: retina, marks: [line2x], cornerRadius: 0, shadow: false, scaleToOneX: true)
        let oneXCG = try require(oneXExport.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(oneXCG.width == 80 && oneXCG.height == 48 && oneXExport.size == NSSize(width: 80, height: 48), "standard 1x export converts Retina raster to logical pixel dimensions")
    }

    static func testLocalToolsAndCanvasExpansionUndo() throws {
        let source = try image(width: 20, height: 16) { _, _ in [30, 40, 50, 255] }
        let marks = [
            EditorMark(tool: .note, points: [CGPoint(x: 1, y: 1)], color: .red, width: 2, text: "Note"),
            EditorMark(tool: .sticker, points: [CGPoint(x: 8, y: 1)], color: .orange, width: 4, text: "⭐️"),
            EditorMark(tool: .magnifier, points: [CGPoint(x: 8, y: 8), CGPoint(x: 18, y: 15)], color: .blue, width: 2),
            EditorMark(tool: .watermark, points: [CGPoint(x: 1, y: 12)], color: .black, width: 3, text: "LOCAL")
        ]
        let view = EditorCanvasView(image: source)
        for mark in marks { view.addAnnotation(mark) }
        let withLocalTools = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(withLocalTools.width == 20 && withLocalTools.height == 16 && view.annotationsForDocument.count == 4, "note, sticker, magnifier and watermark remain editable marks")
        view.extendCanvas(padding: 3, color: .yellow)
        let extended = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(extended.width == 26 && extended.height == 22, "canvas extension adds selected padding")
        try check(pixel(extended, x: 0, y: 0)[0] > 200, "canvas extension paints its selected theme color")
        view.undoLastEdit()
        let undone = try require(view.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        try check(undone.width == 20 && undone.height == 16 && view.annotationsForDocument.count == 4, "undo restores canvas size and local marks")
    }

    static func image(width: Int, height: Int, pixelAt: (Int, Int) -> [UInt8]) throws -> NSImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let color = pixelAt(x, y), i = (y * width + x) * 4
            bytes[i] = color[0]; bytes[i + 1] = color[1]; bytes[i + 2] = color[2]; bytes[i + 3] = color[3]
        }}
        let data = Data(bytes) as CFData
        let provider = try require(CGDataProvider(data: data))
        let cg = try require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { UInt8(($0 * 255).rounded()) }
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw TestFailure(message: "could not encode PNG at \(url.path)", file: #filePath, line: #line)
        }
        try data.write(to: url, options: .atomic)
    }

    static func require<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard let value else { throw TestFailure(message: "Unexpected nil", file: file, line: line) }
        return value
    }
    static func check(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else { throw TestFailure(message: message, file: file, line: line) }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String; let file: StaticString; let line: UInt
    var description: String { "\(file):\(line): \(message)" }
}
