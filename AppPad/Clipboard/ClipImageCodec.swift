import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct CGImageBox: @unchecked Sendable {
    let image: CGImage
}

// HEIC encode (ImageIO, hardware accelerated on Apple Silicon), PNG fallback.
nonisolated enum ClipImageCodec {
    nonisolated struct Encoded {
        let data: Data
        let ext: String
        let width: Int
        let height: Int
    }

    static func encode(_ data: Data, quality: Double) -> Encoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        if let heic = write(image, type: UTType.heic.identifier, quality: quality) {
            return Encoded(data: heic, ext: "heic", width: image.width, height: image.height)
        }
        if let png = write(image, type: UTType.png.identifier, quality: nil) {
            return Encoded(data: png, ext: "png", width: image.width, height: image.height)
        }
        return nil
    }

    private static func write(_ image: CGImage, type: String, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // Downsampled decode: fast, never loads the full bitmap.
    static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func fullImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
