import AppKit

// One list row: source app icon, content (text / image thumbnail / files), saved mark, ⌘n badge.
final class ClipRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("ClipRow")

    private let appIcon = NSImageView()
    private let thumb = ClipThumbView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let savedMark = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let kindIcon = NSImageView()
    private var uuid: String?
    private var hasThumb = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.usesSingleLineMode = true
        savedMark.contentTintColor = .systemYellow
        savedMark.imageScaling = .scaleNone       // frame = image size, see placeSymbol
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.alignment = .right
        kindIcon.imageScaling = .scaleNone
        [appIcon, thumb, titleLabel, savedMark, badgeLabel, kindIcon].forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ item: ClipSummary, index: Int, font: NSFont, showSavedMark: Bool, store: ClipboardStore?) {
        uuid = item.uuid
        appIcon.image = SourceAppDirectory.shared.icon(for: item.sourceBundleID, store: store)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        titleLabel.font = font
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: max(11, font.pointSize * 0.75), weight: .regular)
        badgeLabel.stringValue = index < 10 ? "⌘\((index + 1) % 10)" : ""
        savedMark.isHidden = !(showSavedMark && item.saved)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: max(12, (font.pointSize * 0.8).rounded()), weight: .medium)
        savedMark.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: String(localized: "Saved"))?
            .withSymbolConfiguration(symbolConfig)
        kindIcon.image = NSImage(systemSymbolName: Self.kindSymbol(item.kind), accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        kindIcon.contentTintColor = Self.kindColor(item.kind)

        thumb.image = nil
        thumb.isPhoto = item.kind == .image
        hasThumb = false
        let content: String
        switch item.kind {
        case .text:
            content = Self.singleLine(item.snippet)
        case .image:
            let size = (item.imageWidth != nil && item.imageHeight != nil)
                ? "  \(item.imageWidth!) × \(item.imageHeight!)" : ""
            let name = item.snippet.isEmpty ? String(localized: "Image") : item.snippet   // file name if copied as a file
            content = name + size
            hasThumb = true
            loadThumb(item, store: store)
        case .file:
            let paths = item.snippet.split(separator: "\n").map(String.init)
            content = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            if let first = paths.first {
                thumb.image = NSWorkspace.shared.icon(forFile: first)
                hasThumb = true
            }
        }
        setTitle(label: item.displayName.map(Self.singleLine), content: content, font: font)
        needsLayout = true
    }

    // Labeled items: "label  content", content dimmed.
    private func setTitle(label: String?, content: String, font: NSFont) {
        guard let label else {
            titleLabel.stringValue = content
            return
        }
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let title = NSMutableAttributedString(string: label, attributes: [.font: bold, .foregroundColor: NSColor.labelColor])
        if !content.isEmpty {
            title.append(NSAttributedString(string: "  " + content,
                                            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        titleLabel.attributedStringValue = title
    }

    private func loadThumb(_ item: ClipSummary, store: ClipboardStore?) {
        guard let url = store?.imageURL(for: item) else { return }
        let maxPixel = 160
        if let image = ClipThumbnailCache.shared.cached(uuid: item.uuid, maxPixel: maxPixel) {
            thumb.image = image
            return
        }
        let uuid = item.uuid
        ClipThumbnailCache.shared.load(uuid: uuid, url: url, maxPixel: maxPixel) { [weak self] image in
            guard let self, self.uuid == uuid else { return }   // row was reused
            self.thumb.image = image
        }
    }

    private static func kindSymbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private static func kindColor(_ kind: ClipKind) -> NSColor {
        switch kind {
        case .text: return .systemBlue
        case .image: return .systemGreen
        case .file: return .systemOrange
        }
    }

    nonisolated private static func singleLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // Everything shares one visual midline: icons / thumbnail by their box, text by the middle of
    // its capital letters, SF Symbols by their alignment rect (not the padded image box).
    override func layout() {
        super.layout()
        let b = bounds
        let midY = (b.height / 2).rounded()
        func centered(_ height: CGFloat) -> CGFloat { (midY - height / 2).rounded() }

        let iconSize = min(40, max(22, b.height - 8))
        appIcon.frame = NSRect(x: 10, y: centered(iconSize), width: iconSize, height: iconSize)
        var x = appIcon.frame.maxX + 8

        // Right edge: [★] [kind symbol][⌘n]. Badge slot = width of "⌘0", so symbols line up in every row.
        let badgeFont = badgeLabel.font ?? .systemFont(ofSize: 11)
        let badgeWidth = ceil(("⌘0" as NSString).size(withAttributes: [.font: badgeFont]).width) + 4
        placeText(badgeLabel, x: b.width - badgeWidth - 12, width: badgeWidth, midY: midY)
        let kindFrame = placeSymbol(kindIcon, maxX: badgeLabel.frame.minX - 4, midY: midY)
        var right = kindFrame.minX - 10
        if !savedMark.isHidden {
            let starFrame = placeSymbol(savedMark, maxX: right, midY: midY)
            right = starFrame.minX - 8
        }

        // Thumbnail occupies the same box as the app icon (same size, same midline).
        thumb.isHidden = !hasThumb
        if hasThumb {
            thumb.frame = NSRect(x: x, y: centered(iconSize), width: iconSize, height: iconSize)
            x = thumb.frame.maxX + 10
        } else {
            x += 2
        }
        placeText(titleLabel, x: x, width: max(0, right - x), midY: midY)
    }

    // A label draws its baseline `ascender` below the frame top; put the cap-height middle on midY.
    private func placeText(_ label: NSTextField, x: CGFloat, width: CGFloat, midY: CGFloat) {
        let font = label.font ?? .systemFont(ofSize: 13)
        let height = ceil(label.cell?.cellSize.height ?? (font.ascender - font.descender))
        let y = midY - (font.ascender - font.capHeight / 2)
        label.frame = NSRect(x: x, y: y.rounded(), width: width, height: height)
    }

    // Image view sized to the symbol image; offset so the symbol's alignment rect is centered on midY.
    @discardableResult
    private func placeSymbol(_ view: NSImageView, maxX: CGFloat, midY: CGFloat) -> NSRect {
        let size = view.image?.size ?? NSSize(width: 14, height: 14)
        let align = view.image?.alignmentRect ?? NSRect(origin: .zero, size: size)
        // alignmentRect is in image coordinates (origin bottom-left); our row is flipped.
        let alignCenterFromTop = size.height - align.midY
        let frame = NSRect(x: (maxX - size.width).rounded(), y: (midY - alignCenterFromTop).rounded(),
                           width: size.width, height: size.height)
        view.frame = frame
        return frame
    }
}

// Photo thumbnail shaped like a macOS app icon: the icon body is ~80% of its canvas with a
// continuous corner of ~22% of the body, so a photo drawn that way matches the app icon beside it.
// File icons (isPhoto false) are drawn unclipped, like app icons.
final class ClipThumbView: NSView {
    var image: NSImage? { didSet { updateContents() } }
    var isPhoto = true { didSet { needsLayout = true } }

    private let content = CALayer()
    private static let bodyRatio: CGFloat = 0.805
    private static let cornerRatio: CGFloat = 0.225
    // Not flipped: layer contents then render upright without extra transforms.

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        content.masksToBounds = true
        content.cornerCurve = .continuous
        content.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isPhoto {
            let side = (min(bounds.width, bounds.height) * Self.bodyRatio).rounded()
            content.frame = CGRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(),
                                   width: side, height: side)
            content.cornerRadius = side * Self.cornerRatio
            content.contentsGravity = .resizeAspectFill
        } else {
            content.frame = bounds
            content.cornerRadius = 0
            content.contentsGravity = .resizeAspect
        }
        CATransaction.commit()
        updateContents()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        content.contentsScale = window?.backingScaleFactor ?? 2
        updateContents()
    }

    private func updateContents() {
        let scale = window?.backingScaleFactor ?? 2
        content.contents = image?.layerContents(forContentsScale: scale)
    }
}

// Rounded highlight that stays visible while the search field keeps focus.
final class ClipTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.32).setFill()
        // Inset replaces intercell spacing so the cell is exactly centered in the highlight.
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

// Never takes focus: the search field keeps the caret, arrows / Enter stay with it.
// Hover reports the row under the pointer; a plain left click reports the clicked row.
final class ClipTableView: NSTableView {
    var onHoverRow: ((Int) -> Void)?
    var onClickRow: ((Int) -> Void)?

    private var hoverArea: NSTrackingArea?
    private var lastMouse: NSPoint?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // activeAlways: the panel may not be key when the pointer moves over it.
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Only real pointer movement counts, so scrolling or arrow keys never get overridden
        // by a resting cursor.
        let location = NSEvent.mouseLocation
        defer { lastMouse = location }
        guard location != lastMouse else { return }
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onHoverRow?(row) }
    }

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let row = row(at: convert(event.locationInWindow, from: nil))
        // Modified clicks (e.g. ⌃-click menu) and clicks on empty space keep default behavior.
        guard modifiers.isEmpty, row >= 0 else {
            super.mouseDown(with: event)
            return
        }
        onClickRow?(row)
    }
}
