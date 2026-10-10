import AppKit

// Workflow icons: 512×512, rounded rectangle on the macOS icon grid (body ~80% of the canvas),
// so they line up with app icons in the same list.
enum WorkflowIcon {
    static let pixels = 512
    nonisolated private static let bodyRatio: CGFloat = 0.805
    nonisolated private static let cornerRatio: CGFloat = 0.225

    private static var cache: [String: NSImage] = [:]

    // Custom PNG if set, otherwise a generated icon (step-kind color + SF Symbol).
    static func image(for workflow: Workflow) -> NSImage {
        let key: String
        if let data = workflow.icon {
            // Cheap fingerprint (rows re-render often; don't hash the whole PNG).
            var hasher = Hasher()
            hasher.combine(data.prefix(128))
            hasher.combine(data.dropFirst(data.count / 2).prefix(128))
            key = "png:\(workflow.id.uuidString):\(data.count):\(hasher.finalize())"
        } else {
            key = "gen:\(workflow.symbolName):\(workflow.steps.first?.kind.rawValue ?? "")"
        }
        if let cached = cache[key] { return cached }
        let image = workflow.icon.flatMap { NSImage(data: $0) } ?? generated(for: workflow)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }

    // MARK: - Generated

    private static func generated(for workflow: Workflow) -> NSImage {
        let colors = palette(workflow.steps.first?.kind)
        return drawGenerated(symbol: workflow.symbolName, top: colors.top, bottom: colors.bottom)
    }

    // Nonisolated: NSImage may run the drawing handler off the main thread.
    nonisolated private static func drawGenerated(symbol: String, top: NSColor, bottom: NSColor) -> NSImage {
        let size: CGFloat = 512
        let colors = (top: top, bottom: bottom)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let body = bodyRect(canvas: size)
            let path = NSBezierPath(roundedRect: body, xRadius: body.width * cornerRatio, yRadius: body.width * cornerRatio)
            NSGradient(starting: colors.top, ending: colors.bottom)?.draw(in: path, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.4, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let g = glyph.size
                glyph.draw(in: NSRect(x: body.midX - g.width / 2, y: body.midY - g.height / 2,
                                      width: g.width, height: g.height))
            }
            return true
        }
    }

    private static func palette(_ kind: WorkflowStepKind?) -> (top: NSColor, bottom: NSColor) {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        switch kind {
        case .shell: return (rgb(0x48484A), rgb(0x1C1C1E))
        case .appleScript: return (rgb(0x9A9AA0), rgb(0x5A5A60))
        case .shortcut: return (rgb(0xFF5E7E), rgb(0xFF8A3D))
        case .http: return (rgb(0x3D9BFF), rgb(0x5E5CE6))
        case .builtin: return (rgb(0x34D399), rgb(0x1F8A5B))
        case nil: return (rgb(0xC77DFF), rgb(0x7B3FE4))
        }
    }

    nonisolated private static func bodyRect(canvas: CGFloat) -> NSRect {
        let side = (canvas * bodyRatio).rounded()
        let inset = ((canvas - side) / 2).rounded()
        return NSRect(x: inset, y: inset, width: side, height: side)
    }

    // MARK: - Import

    // Any image → 512×512 PNG. Images that already have transparent corners (exported app icons)
    // are only scaled; everything else is center-cropped into the rounded body.
    static func makePNG(from url: URL) -> Data? {
        guard let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)

        let canvas = CGFloat(pixels)
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let ctx = context.cgContext
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        if hasTransparentCorners(cg) {
            let scale = min(canvas / w, canvas / h)
            let size = CGSize(width: w * scale, height: h * scale)
            ctx.draw(cg, in: CGRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2,
                                    width: size.width, height: size.height))
        } else {
            let body = bodyRect(canvas: canvas)
            let radius = body.width * cornerRatio
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
            let scale = max(body.width / w, body.height / h)   // aspect fill
            let size = CGSize(width: w * scale, height: h * scale)
            ctx.draw(cg, in: CGRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2,
                                    width: size.width, height: size.height))
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // Corner transparent + center opaque → already shaped like an icon.
    private static func hasTransparentCorners(_ image: CGImage) -> Bool {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * side + x) * 4 + 3] }
        let corners = [alpha(0, 0), alpha(side - 1, 0), alpha(0, side - 1), alpha(side - 1, side - 1)]
        return corners.allSatisfy { $0 < 16 } && alpha(side / 2, side / 2) > 200
    }
}
