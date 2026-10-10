import AppKit

// In-panel dialog (no separate window, so the non-activating panel keeps focus).
// Optional checklist for leftover files. Enter = confirm, Esc = cancel (routed by the view controller).
final class ConfirmOverlayView: FlippedView {
    nonisolated struct CheckItem: Sendable {
        let url: URL
        let checked: Bool
    }

    var onConfirm: (([URL]) -> Void)?
    var onCancel: (() -> Void)?

    private let box = FolderBoxView()
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let messageLabel: NSTextField
    private let scrollView = NSScrollView()
    private let listView = FlippedView()
    private var checkboxes: [(NSButton, URL)] = []
    private let confirmButton: NSButton
    private let cancelButton: NSButton
    private let cornerRadius: CGFloat
    private let showsCancel: Bool

    private static let rowHeight: CGFloat = 22

    init(icon: NSImage?, title: String, message: String, items: [CheckItem],
         confirmTitle: String, destructive: Bool, showsCancel: Bool = true, cornerRadius: CGFloat) {
        titleLabel = NSTextField(labelWithString: title)
        messageLabel = NSTextField(wrappingLabelWithString: message)
        confirmButton = NSButton(title: confirmTitle, target: nil, action: nil)
        cancelButton = NSButton(title: String(localized: "Cancel"), target: nil, action: nil)
        self.cornerRadius = cornerRadius
        self.showsCancel = showsCancel
        super.init(frame: .zero)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor

        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        confirmButton.bezelStyle = .rounded
        confirmButton.hasDestructiveAction = destructive
        confirmButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.isHidden = !showsCancel

        addSubview(box)
        [iconView, titleLabel, messageLabel, confirmButton, cancelButton].forEach { box.addSubview($0) }

        if !items.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for item in items {
                let display = item.url.path.replacingOccurrences(of: home, with: "~")
                let checkbox = NSButton(checkboxWithTitle: display, target: nil, action: nil)
                checkbox.state = item.checked ? .on : .off
                checkbox.font = .systemFont(ofSize: 11)
                checkbox.lineBreakMode = .byTruncatingMiddle
                listView.addSubview(checkbox)
                checkboxes.append((checkbox, item.url))
            }
            scrollView.documentView = listView
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            box.addSubview(scrollView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let width = min(440, bounds.width - 40)
        let listHeight = checkboxes.isEmpty ? 0 : min(CGFloat(checkboxes.count) * Self.rowHeight + 8, 170)
        let messageHeight = messageLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 40, height: 400)).height ?? 32
        let height = 20 + 56 + 10 + 22 + 6 + messageHeight + (listHeight > 0 ? listHeight + 12 : 0) + 20 + 28 + 18
        box.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)

        var y: CGFloat = 20
        iconView.frame = NSRect(x: (width - 56) / 2, y: y, width: 56, height: 56)
        y += 56 + 10
        titleLabel.frame = NSRect(x: 20, y: y, width: width - 40, height: 22)
        y += 22 + 6
        messageLabel.frame = NSRect(x: 20, y: y, width: width - 40, height: messageHeight)
        y += messageHeight
        if listHeight > 0 {
            y += 12
            scrollView.frame = NSRect(x: 20, y: y, width: width - 40, height: listHeight)
            let contentWidth = scrollView.contentSize.width
            listView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: CGFloat(checkboxes.count) * Self.rowHeight + 8)
            for (index, (checkbox, _)) in checkboxes.enumerated() {
                checkbox.frame = NSRect(x: 4, y: 4 + CGFloat(index) * Self.rowHeight, width: contentWidth - 8, height: Self.rowHeight)
            }
            y += listHeight
        }
        y += 20
        let buttonWidth: CGFloat = 120
        if showsCancel {
            cancelButton.frame = NSRect(x: width / 2 - buttonWidth - 6, y: y, width: buttonWidth, height: 28)
            confirmButton.frame = NSRect(x: width / 2 + 6, y: y, width: buttonWidth, height: 28)
        } else {
            confirmButton.frame = NSRect(x: (width - buttonWidth) / 2, y: y, width: buttonWidth, height: 28)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    @objc func confirm() {
        let urls = checkboxes.filter { $0.0.state == .on }.map(\.1)
        onConfirm?(urls)
    }

    @objc func cancel() {
        onCancel?()
    }
}
