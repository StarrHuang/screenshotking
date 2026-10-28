import AppKit
import CoreGraphics
import Darwin

public enum StitchDirection: Sendable, Equatable {
    case vertical
    case horizontal
}

public enum ImageProcessingError: Error, LocalizedError {
    case emptyInput
    case unreadableImage
    case incompatibleDimensions

    public var errorDescription: String? {
        switch self {
        case .emptyInput: return L("至少需要一张图片。")
        case .unreadableImage: return L("无法解码输入图片。")
        case .incompatibleDimensions: return L("纵向拼接时图片宽度必须相同，横向拼接时图片高度必须相同。")
        }
    }
}

/// Pixel-based long-image stitching. Adjacent images are aligned at their leading edge;
/// a matching overlap is removed, and images without a detectable overlap are appended.
public enum ImageProcessing {
    /// Crops a rectangle in top-left-origin image pixel coordinates.
    public static func crop(image: NSImage, rect: CGRect) throws -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ImageProcessingError.unreadableImage }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let topLeft = rect.integral.intersection(bounds)
        guard topLeft.width > 0, topLeft.height > 0 else { throw ImageProcessingError.incompatibleDimensions }
        // CGImage raster coordinates use the pixel image's top-left origin.
        let cgRect = topLeft
        guard let cropped = source.cropping(to: cgRect) else { throw ImageProcessingError.unreadableImage }
        let scaleX = image.size.width / CGFloat(source.width)
        let scaleY = image.size.height / CGFloat(source.height)
        return NSImage(cgImage: cropped, size: NSSize(width: CGFloat(cropped.width) * scaleX, height: CGFloat(cropped.height) * scaleY))
    }

    public static func stitch(images: [NSImage], direction: StitchDirection) throws -> NSImage {
        guard !images.isEmpty else { throw ImageProcessingError.emptyInput }
        let cgImages = try images.map { image -> CGImage in
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                throw ImageProcessingError.unreadableImage
            }
            return cg
        }
        let width = cgImages[0].width
        let height = cgImages[0].height
        for image in cgImages.dropFirst() {
            switch direction {
            case .vertical where image.width != width: throw ImageProcessingError.incompatibleDimensions
            case .horizontal where image.height != height: throw ImageProcessingError.incompatibleDimensions
            default: break
            }
        }

        let pixels = try cgImages.map(rgbaPixels)
        var placements: [(pixels: [UInt8], offset: Int)] = []
        var total = direction == .vertical ? height : width
        placements.append((pixels[0], 0))
        for index in 1..<cgImages.count {
            let overlap = bestOverlap(
                previous: placements[index - 1].pixels,
                next: pixels[index],
                width: width,
                height: height,
                direction: direction
            )
            let advance = (direction == .vertical ? height : width) - overlap
            placements.append((pixels[index], total - (direction == .vertical ? height : width) + advance))
            total += advance
        }

        let outputWidth = direction == .vertical ? width : total
        let outputHeight = direction == .vertical ? total : height
        var outputPixels = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        outputPixels.withUnsafeMutableBytes { outputBuffer in
            for placement in placements {
                placement.pixels.withUnsafeBytes { sourceBuffer in
                    for sourceY in 0..<height {
                        let from = sourceY * width * 4
                        let outputX = direction == .vertical ? 0 : placement.offset
                        let outputY = direction == .vertical ? placement.offset + sourceY : sourceY
                        let to = (outputY * outputWidth + outputX) * 4
                        memcpy(outputBuffer.baseAddress!.advanced(by: to), sourceBuffer.baseAddress!.advanced(by: from), width * 4)
                    }
                }
            }
        }
        let outputData = Data(outputPixels) as CFData
        guard let provider = CGDataProvider(data: outputData),
              let output = CGImage(width: outputWidth, height: outputHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outputWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ImageProcessingError.unreadableImage
        }
        let scaleX = images[0].size.width / CGFloat(width)
        let scaleY = images[0].size.height / CGFloat(height)
        let pointSize: NSSize
        switch direction {
        case .vertical: pointSize = NSSize(width: CGFloat(outputWidth) * scaleX, height: CGFloat(outputHeight) * scaleY)
        case .horizontal: pointSize = NSSize(width: CGFloat(outputWidth) * scaleX, height: CGFloat(outputHeight) * scaleY)
        }
        return NSImage(cgImage: output, size: pointSize)
    }

    private static func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ImageProcessingError.unreadableImage }
        return data
    }

    private static func bestOverlap(previous: [UInt8], next: [UInt8], width: Int, height: Int, direction: StitchDirection) -> Int {
        let axisLength = direction == .vertical ? height : width
        guard axisLength >= 8 else { return 0 }
        let maximum = axisLength - 4
        var bestMatch: (overlap: Int, meanError: Double)?
        for overlap in stride(from: maximum, through: 4, by: -1) {
            var error: UInt64 = 0
            var samples: UInt64 = 0
            // Search a larger overlap range with a smaller, bounded sample grid. At 4K
            // dimensions this evaluates fewer pixels than the old 1200/half-axis cap.
            let stridePixels = max(1, (direction == .vertical ? width : height) / 80)
            if direction == .vertical {
                for y in 0..<overlap where y % max(1, overlap / 64) == 0 {
                    let oldY = height - overlap + y
                    for x in stride(from: 0, to: width, by: stridePixels) {
                        let a = (oldY * width + x) * 4, b = (y * width + x) * 4
                        error += UInt64(abs(Int(previous[a]) - Int(next[b])) + abs(Int(previous[a + 1]) - Int(next[b + 1])) + abs(Int(previous[a + 2]) - Int(next[b + 2])))
                        samples += 3
                    }
                }
            } else {
                for x in 0..<overlap where x % max(1, overlap / 64) == 0 {
                    let oldX = width - overlap + x
                    for y in stride(from: 0, to: height, by: stridePixels) {
                        let a = (y * width + oldX) * 4, b = (y * width + x) * 4
                        error += UInt64(abs(Int(previous[a]) - Int(next[b])) + abs(Int(previous[a + 1]) - Int(next[b + 1])) + abs(Int(previous[a + 2]) - Int(next[b + 2])))
                        samples += 3
                    }
                }
            }
            guard samples > 0 else { continue }
            let meanError = Double(error) / Double(samples)
            if bestMatch == nil || meanError < bestMatch!.meanError || (meanError == bestMatch!.meanError && overlap > bestMatch!.overlap) {
                bestMatch = (overlap, meanError)
            }
        }
        guard let bestMatch, bestMatch.meanError <= 18 else { return 0 }
        return bestMatch.overlap
    }
}
