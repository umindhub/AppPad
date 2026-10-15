import AppKit
import UniformTypeIdentifiers

// Right-hand preview: full text, larger image, or file list, plus metadata.
final class ClipPreviewView: FlippedView {
    var onEscape: (() -> Void)?

    private let textScroll = NSScrollView()
    private let textView = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private let imageView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private var uuid: String?

    private static let maxPreviewChars = 200_000
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.drawsBackground = false
        textScroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textColor = .labelColor
        textView.onEscape = { [weak self] in self?.onEscape?() }
        textScroll.documentView = textView

        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignTop

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.maximumNumberOfLines = 3
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        pathLabel.isHidden = true

        [textScroll, imageView, pathLabel, metaLabel, hintLabel].forEach { addSubview($0) }
        show(nil, font: .systemFont(ofSize: 15), store: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ item: ClipItem?, font: NSFont, store: ClipboardStore?) {
        uuid = item?.uuid
        imageView.image = nil
        guard let item else {
            textScroll.isHidden = true
            imageView.isHidden = true
            metaLabel.stringValue = ""
            hintLabel.isHidden = true
            pathLabel.isHidden = true
            return
        }
        hintLabel.isHidden = false
        // Folder / file location under the image (⌘↩ reveals it in Finder).
        let location = item.locationPath
        pathLabel.stringValue = location.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
        pathLabel.toolTip = location
        var hint = String(localized: "↩ Paste   ⌘S Save   ⌘⇧⌫ Delete") + "   " + String(localized: "⌘↩ Edit")
        if location != nil { hint += "   " + String(localized: "⌘⇧↩ Show in Finder") }
        hintLabel.stringValue = hint
        // Older file items that point to an image: preview the image itself.
        let fileImage = item.kind == .file ? Self.firstImageFile(item) : nil
        switch item.kind {
        case .file where fileImage != nil:
            textScroll.isHidden = true
            imageView.isHidden = false
            pathLabel.isHidden = false
            loadImage(uuid: item.uuid, url: fileImage!)
        case .text, .file:
            textScroll.isHidden = false
            imageView.isHidden = true
            pathLabel.isHidden = true      // file list is already the text
            var text = item.text ?? ""
            if text.count > Self.maxPreviewChars { text = String(text.prefix(Self.maxPreviewChars)) + "\n…" }
            textView.string = text
            textView.font = font
            textView.textColor = .labelColor
            textView.scrollToBeginningOfDocument(nil)
        case .image:
            textScroll.isHidden = true
            imageView.isHidden = false
            pathLabel.isHidden = location == nil
            if let url = store?.imageURL(for: item) { loadImage(uuid: item.uuid, url: url) }
        }
        metaLabel.stringValue = Self.meta(for: item)
        needsLayout = true
    }

    private static func firstImageFile(_ item: ClipItem) -> URL? {
        guard let path = (item.text ?? "").split(separator: "\n").first else { return nil }
        let url = URL(fileURLWithPath: String(path))
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) == true ? url : nil
    }

    private func loadImage(uuid: String, url: URL) {
        let maxPixel = 1600
        if let image = ClipThumbnailCache.shared.cached(uuid: uuid, maxPixel: maxPixel) {
            imageView.image = image
            return
        }
        // Show the small row thumbnail while the larger one decodes.
        imageView.image = ClipThumbnailCache.shared.cached(uuid: uuid, maxPixel: 160)
        ClipThumbnailCache.shared.load(uuid: uuid, url: url, maxPixel: maxPixel) { [weak self] image in
            guard let self, self.uuid == uuid, let image else { return }
            self.imageView.image = image
        }
    }

    private static func meta(for item: ClipItem) -> String {
        var parts: [String] = []
        if let label = item.name, !label.isEmpty { parts.append(label) }
        if let name = item.sourceName { parts.append(name) }
        parts.append(dateFormatter.string(from: Date(timeIntervalSince1970: item.lastUsedAt)))
        switch item.kind {
        case .text:
            parts.append(String(localized: "\((item.text ?? "").count) characters"))
        case .image:
            if let name = item.text, !name.isEmpty { parts.append(name) }
            if let w = item.imageWidth, let h = item.imageHeight { parts.append("\(w) × \(h)") }
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
            parts.append("\(size) \((item.imageExt ?? "").uppercased())")
        case .file:
            let count = (item.text ?? "").split(separator: "\n").count
            parts.append(String(localized: "\(count) items"))
        }
        if item.saved { parts.append(String(localized: "Saved")) }
        return parts.joined(separator: " · ")
    }

    override func layout() {
        super.layout()
        let b = bounds
        hintLabel.frame = NSRect(x: 0, y: b.height - 16, width: b.width, height: 16)
        let metaHeight: CGFloat = 34
        metaLabel.frame = NSRect(x: 0, y: hintLabel.frame.minY - metaHeight - 4, width: b.width, height: metaHeight)
        var contentBottom = metaLabel.frame.minY - 10
        if !pathLabel.isHidden {
            let h = ceil(pathLabel.cell?.cellSize.height ?? 16)
            pathLabel.frame = NSRect(x: 0, y: contentBottom - h, width: b.width, height: h)
            contentBottom = pathLabel.frame.minY - 8
        }
        let content = NSRect(x: 0, y: 0, width: b.width, height: max(0, contentBottom))
        textScroll.frame = content
        imageView.frame = content
    }
}

// Selectable preview text; Esc returns focus to the search field.
final class PreviewTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
