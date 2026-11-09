import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DesignRenderError: LocalizedError {
    case cannotLoadImage(String)
    case cannotCreateContext
    case cannotWriteImage(String)

    public var errorDescription: String? {
        switch self {
        case .cannotLoadImage(let path):
            return "Could not read the image at \(path)."
        case .cannotCreateContext:
            return "Could not create a graphics context."
        case .cannotWriteImage(let path):
            return "Could not write the image to \(path)."
        }
    }
}

/// Renders the native layer stack into the same square source picture the C# engine
/// consumes: the square's centre is the disc centre and its side spans
/// `2 × contentOuterRadiusMm`. Layer order is topmost-first, exactly like `.discproj`.
public enum DesignRenderer {
    public static let maxDecodeWidth = 4096

    public static func imagePixelSize(at path: String) -> CGSize? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0
        else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    public static func loadImage(at path: String, maxPixel: Int = maxDecodeWidth) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func renderComposite(
        layers: [ProjectLayer],
        outerRadiusMm: Double,
        outputSize: Int
    ) throws -> CGImage {
        guard outerRadiusMm.isFinite, outerRadiusMm > 0, outputSize > 0 else {
            throw DesignRenderError.cannotCreateContext
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: outputSize * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw DesignRenderError.cannotCreateContext
        }

        context.clear(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        // Work in screen coordinates: +x right, +y down.
        context.translateBy(x: 0, y: CGFloat(outputSize))
        context.scaleBy(x: 1, y: -1)

        let pixelsPerMm = Double(outputSize) / (2.0 * outerRadiusMm)
        let center = Double(outputSize) / 2.0
        let bounds = Double(outputSize)

        for layer in layers.reversed() where layer.visible {
            guard let image = loadImage(at: layer.imagePath) else { continue }
            let pixelWidth = Double(image.width)
            let pixelHeight = Double(image.height)
            guard pixelWidth > 0, pixelHeight > 0 else { continue }

            // Fit rule used by the WPF DesignComposer: the larger dimension spans the
            // content ring diameter at scale 1.
            let diameterMm = 2.0 * outerRadiusMm
            let baseWidthMm = pixelWidth >= pixelHeight
                ? diameterMm
                : diameterMm * pixelWidth / pixelHeight
            let baseHeightMm = pixelWidth >= pixelHeight
                ? diameterMm * pixelHeight / pixelWidth
                : diameterMm

            let width = baseWidthMm * layer.scale * pixelsPerMm
            let height = baseHeightMm * layer.scale * pixelsPerMm
            guard width > 0, height > 0 else { continue }

            let centerX = center + layer.translateXMm * pixelsPerMm
            let centerY = center + layer.translateYMm * pixelsPerMm
            let rect = CGRect(
                x: -width / 2,
                y: -height / 2,
                width: width,
                height: height
            )
            // Keep absurd transforms from turning into pathological draw calls.
            guard rect.origin.x.isFinite, rect.origin.y.isFinite else { continue }
            if abs(centerX) > bounds * 8 || abs(centerY) > bounds * 8 { continue }

            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: layer.rotationDeg * .pi / 180.0)
            context.draw(image, in: rect)
            context.restoreGState()
        }

        guard let output = context.makeImage() else {
            throw DesignRenderError.cannotCreateContext
        }
        return output
    }

    /// Projects the composite through the disc tone mapping and masks it to the
    /// recordable annulus. This is the native preview used for BD-R (the engine has no
    /// standalone BD preview command) and for the live tone card.
    public static func renderDiscPreview(
        composite: CGImage,
        family: DiscFamily,
        geometry: ProjectGeometry,
        tone: ToneProfile,
        invertMapping: Bool,
        size: Int
    ) throws -> CGImage {
        let outerRadius = geometry.contentOuterRadiusMm(family: family)
        guard outerRadius > 0, size > 0 else { throw DesignRenderError.cannotCreateContext }
        let innerRadius = geometry.innerRadiusMm
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw DesignRenderError.cannotCreateContext
        }

        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.draw(composite, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let base = context.makeImage() else {
            throw DesignRenderError.cannotCreateContext
        }
        guard let sourceData = base.dataProvider?.data,
              let sourcePointer = CFDataGetBytePtr(sourceData)
        else {
            throw DesignRenderError.cannotCreateContext
        }

        var output = [UInt8](repeating: 0, count: size * size * 4)
        let pixelsPerMm = Double(size) / (2.0 * outerRadius)
        let center = Double(size) / 2.0
        let sourceBytesPerRow = base.bytesPerRow
        let outputBytesPerRow = size * 4
        let innerSquared = innerRadius * innerRadius
        let outerSquared = outerRadius * outerRadius

        output.withUnsafeMutableBytes { raw in
            guard let destination = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<size {
                let dy = (Double(y) + 0.5 - center) / pixelsPerMm
                let row = y * outputBytesPerRow
                let sourceRow = y * sourceBytesPerRow
                for x in 0..<size {
                    let dx = (Double(x) + 0.5 - center) / pixelsPerMm
                    let radiusSquared = dx * dx + dy * dy
                    let offset = row + x * 4
                    if radiusSquared < innerSquared || radiusSquared > outerSquared {
                        destination[offset] = 0
                        destination[offset + 1] = 0
                        destination[offset + 2] = 0
                        destination[offset + 3] = 0
                        continue
                    }
                    let source = sourceRow + x * 4
                    let premultipliedLuminance =
                        0.2126 * Double(sourcePointer[source])
                        + 0.7152 * Double(sourcePointer[source + 1])
                        + 0.0722 * Double(sourcePointer[source + 2])
                    // Premultiplied RGB composited against a white disc surface.
                    let onWhite = 255.0 - Double(sourcePointer[source + 3]) + premultipliedLuminance
                    let gray = UInt8(min(max(onWhite.rounded(), 0), 255))
                    let index = Int64(y * size + x)
                    var mapped = tone.quantizedGray(gray: gray, sampleIndex: index)
                    if family == .bd && invertMapping {
                        mapped = 255 - mapped
                    }
                    destination[offset] = mapped
                    destination[offset + 1] = mapped
                    destination[offset + 2] = mapped
                    destination[offset + 3] = 255
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outputBytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            throw DesignRenderError.cannotCreateContext
        }
        return image
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try AppPaths.ensureDirectory(url.deletingLastPathComponent())
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DesignRenderError.cannotWriteImage(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesignRenderError.cannotWriteImage(url.path)
        }
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func thumbnailBase64(
        layers: [ProjectLayer],
        outerRadiusMm: Double,
        size: Int = 256
    ) -> String? {
        guard !layers.isEmpty,
              let image = try? renderComposite(layers: layers, outerRadiusMm: outerRadiusMm, outputSize: size),
              let data = pngData(image)
        else { return nil }
        return data.base64EncodedString()
    }
}
