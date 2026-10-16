import AppKit
import os

// Why a panel closed (Console / `log stream`, category "close").
// Callers just pass a String, so other files need no `import os`.
enum CloseLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppPad", category: "close")

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

// Owns the panel, the installed-app catalog, the layout and launch stats.
final class LaunchpadController: NSObject, NSWindowDelegate {
    static let cornerRadius: CGFloat = 26
    // Used when the panel fills the visible frame: smaller than macOS 26 window corners,
    // so maximized windows underneath don't peek out at the corners.
    static let filledCornerRadius: CGFloat = 12

    var onOpenSettings: (() -> Void)?
    var onRequestShortcut: ((AppInfo) -> Void)?
    // ⌘⇧J (-1) / ⌘⇧K (+1): previous / next panel (Launchpad → Clipboard → Workflows).
    var onSwitchPanel: ((Int) -> Void)?

    private let prefs = Preferences.shared
    private let panel: LaunchpadPanel
    private let container = FlippedView()
    private let background = LaunchpadBackgroundView()
    private let viewController = LaunchpadViewController()
    private let layoutStore: LayoutStore
    private let stats: LaunchStats

    private var apps: [AppInfo] = []
    private var appsByKey: [String: AppInfo] = [:]
    private var searchIndex = SearchIndex(apps: [])
    private var folderEntryCache: [String: SearchIndex.Entry] = [:]
    private var watcher: AppDirectoryWatcher?
    private var rescanTask: Task<Void, Never>?
    private var rescanDebounce: Task<Void, Never>?
    private var lastCapacity = 0
    private var isHiding = false
    // When the panel last closed because it lost key (click outside).
    private var lastOutsideClose: TimeInterval = -1
    private var didWarmUp = false
    private var isWarmingUp = false
    // Catalog scanned + wallpaper blurred (a cold launch must not open an empty grid).
    private var isReady = false
    private var pendingReadyShow: (() -> Void)?
    // Animated hide in flight (Dock toggle / click outside).
    private var isFadingOut = false
    // Closes on a Space switch (macOS 15 Launchpad behavior).
    private var spaceGuard: PanelSpaceGuard?

    private static let showDuration: TimeInterval = 0.25
    private static let hideDuration: TimeInterval = 0.2
    // Click on empty space: slower, calmer fade out.
    static let backgroundClickHideDuration: TimeInterval = 0.25

    var capacity: Int { max(1, prefs.gridColumns * prefs.gridRows) }

    override init() {
        let dir = AppEnvironment.supportDirectory
        layoutStore = LayoutStore(fileURL: dir.appendingPathComponent("layout.json"))
        stats = LaunchStats(directory: dir)
        panel = LaunchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        super.init()
    }

    func start() {
        // Blur wallpapers now, not on the first show.
        WallpaperBlurCache.shared.start()
        viewController.controller = self

        // Rounded container: background (wallpaper / color) + content.
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        let content = viewController.view
        content.autoresizingMask = [.width, .height]
        container.addSubview(background)
        container.addSubview(content)
        panel.contentView = container
        background.frame = container.bounds
        content.frame = container.bounds
        panel.morphBackground = background
        panel.morphContent = content
        // Late wallpaper (cache miss) may change light / dark text.
        background.onWallpaperApplied = { [weak self] in self?.applyAppearance() }

        panel.delegate = self
        panel.keyHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }
        panel.eventObserver = { [weak self] event in
            self?.viewController.observeOptionHold(event)
        }
        PinchGestureMonitor.shared.onTap = { [weak self] in self?.handleTrackpadTap() }
        // Instant close, no fade (the desktop already changed).
        spaceGuard = PanelSpaceGuard(panel: panel) { [weak self] in
            CloseLog.note("launchpad: space changed")
            self?.hide()
        }

        lastCapacity = capacity
        applyAppearance()
        viewController.reloadAll()
        rescan()

        let paths = AppScanner.roots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        watcher = AppDirectoryWatcher(paths: paths) { [weak self] in
            self?.scheduleRescan()
        }
    }

    // MARK: - Catalog

    private func rescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) { () -> ([AppInfo], SearchIndex) in
                let apps = AppScanner.scanAll()
                return (apps, SearchIndex(apps: apps))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(apps: scanned.0, index: scanned.1)
        }
    }

    // Coalesce FSEvents bursts (installers touch many files).
    private func scheduleRescan() {
        rescanDebounce?.cancel()
        rescanDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    private func apply(apps newApps: [AppInfo], index: SearchIndex) {
        apps = newApps
        appsByKey = Dictionary(newApps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        searchIndex = index
        stats.seedIfNeeded(newApps)
        IconCache.shared.invalidate()
        layoutStore.reconcile(apps: newApps, capacity: capacity)
        viewController.reloadAll()
        warmUpIfNeeded()
    }

    // MARK: - Launch warm-up

    // The first show used to pay for the window backing store, the first layout/draw of every
    // layer and the material views. Do it once right after launch, invisibly (alpha 0, not key,
    // click-through), then order out. Any real show takes over immediately.
    private func warmUpIfNeeded() {
        guard !didWarmUp else { return }
        didWarmUp = true
        Task { [weak self] in
            let screen = PanelScreen.target()
            if let screen {
                let params = PanelBackgroundSpec.current(for: .launchpad).blurParams
                _ = await WallpaperBlurCache.shared.image(for: screen, params: params)
            }
            guard let self else { return }
            self.isReady = true
            // Cold launch from the Dock: show right away, no hidden warm-up pass.
            if let pending = self.pendingReadyShow {
                self.pendingReadyShow = nil
                pending()
                return
            }
            guard let screen, !self.panel.isVisible else { return }
            self.isWarmingUp = true
            self.applyAppearance()
            self.applyFrame(self.targetFrame(on: screen), on: screen, display: false)
            self.viewController.prepareForShow(resetToFirstPage: true)
            self.panel.alphaValue = 0
            self.panel.ignoresMouseEvents = true
            self.panel.orderFront(nil)
            self.container.layoutSubtreeIfNeeded()
            self.panel.displayIfNeeded()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(200))
            self.endWarmUp(orderOut: true)
        }
    }

    // orderOut only if no real show happened meanwhile.
    private func endWarmUp(orderOut: Bool) {
        guard isWarmingUp else { return }
        isWarmingUp = false
        if orderOut { panel.orderOut(nil) }
        panel.ignoresMouseEvents = false
    }

    func displayPages() -> [[GridEntry]] {
        layoutStore.layout.pages.map { page in page.compactMap(entry(for:)) }
    }

    private func entry(for item: LayoutItem) -> GridEntry? {
        switch item {
        case .app(let key):
            return appsByKey[key].map { .app($0) }
        case .folder(let folder):
            let list = folderApps(folder)
            return list.isEmpty ? nil : .folder(folder, list)
        }
    }

    func app(forKey key: String) -> AppInfo? {
        appsByKey[key]
    }

    func layoutItems(onPage page: Int) -> [LayoutItem] {
        layoutStore.items(onPage: page)
    }

    func folder(id: String) -> FolderItem? {
        layoutStore.folder(id: id)
    }

    func folderApps(_ folder: FolderItem) -> [AppInfo] {
        folder.apps.compactMap { appsByKey[$0] }
    }

    // Every app, most used first (Workflow panel with an empty search).
    func appsByFrecency() -> [AppInfo] {
        let now = Date()
        return apps
            .map { (app: $0, score: stats.score(for: $0.key, now: now)) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.app.name.localizedStandardCompare(b.app.name) == .orderedAscending
            }
            .map(\.app)
    }

    // MARK: - Frecency shared with workflows

    // Workflow panel: every app with its match score (0 = no match; empty query → all match).
    func scoredApps(matching query: String) -> [(app: AppInfo, match: Int)] {
        let normalized = SearchIndex.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return apps.map { (app: $0, match: 1) } }
        // "final-cut-pro" (a name completed in the panel) also matches as "final cut pro".
        let spaced = normalized.contains("-") ? normalized.replacingOccurrences(of: "-", with: " ") : nil
        var result: [(app: AppInfo, match: Int)] = []
        for app in apps {
            var match = searchIndex.matchScore(app.key, query: normalized)
            if let spaced {
                if SearchIndex.normalize(app.name.split(whereSeparator: \.isWhitespace).joined(separator: "-")) == normalized {
                    match = 130   // exact completed name
                } else {
                    match = max(match, searchIndex.matchScore(app.key, query: spaced))
                }
            }
            if match > 0 { result.append((app: app, match: match)) }
        }
        return result
    }

    func frecency(_ key: String, now: Date = Date()) -> Double {
        stats.score(for: key, now: now)
    }

    // A workflow run from the panel counts like an app launch.
    func recordUse(_ key: String) {
        stats.record(key, manual: true)
    }

    // New workflows start like user-installed apps (2) so they aren't buried below the apps.
    func seedWorkflows(_ keys: [String]) {
        stats.seedIfNeeded(keys: keys, score: 2)
    }

    // Rank: match quality, then frecency, then name. "A | B" / "A || B" matches either term.
    func search(_ query: String) -> [AppInfo] {
        let terms = SearchIndex.queryTerms(query)
        guard !terms.isEmpty else { return [] }
        return rankedApps(terms: terms, now: Date()).map(\.app)
    }

    private func rankedApps(terms: [String], now: Date) -> [(app: AppInfo, rank: SearchRank)] {
        apps.compactMap { app -> (app: AppInfo, rank: SearchRank)? in
            let match = searchIndex.matchScore(app.key, terms: terms)
            guard match > 0 else { return nil }
            return (app: app, rank: SearchRank(match: match, frecency: stats.score(for: app.key, now: now), name: app.name))
        }
        .sorted { $0.rank < $1.rank }
    }

    // Launchpad search: top-level apps plus folders, each folder once. A folder shows up when one
    // of its apps matches (ranked like its best app, which is highlighted when opened) or when its
    // own name matches (then best is nil unless an app inside matches too).
    func searchEntries(_ query: String) -> [(entry: GridEntry, best: AppInfo?)] {
        let terms = SearchIndex.queryTerms(query)
        guard !terms.isEmpty else { return [] }
        let now = Date()

        var folders: [FolderItem] = []
        var folderOf: [String: FolderItem] = [:]
        for page in layoutStore.layout.pages {
            for case .folder(let folder) in page {
                folders.append(folder)
                for key in folder.apps { folderOf[key] = folder }
            }
        }

        // Ranked apps: top-level ones become results, the first one per folder is its best.
        var candidates: [(rank: SearchRank, entry: GridEntry, best: AppInfo?)] = []
        var bestInFolder: [String: (app: AppInfo, rank: SearchRank)] = [:]
        for hit in rankedApps(terms: terms, now: now) {
            if let folder = folderOf[hit.app.key] {
                if bestInFolder[folder.id] == nil { bestInFolder[folder.id] = hit }
            } else {
                candidates.append((rank: hit.rank, entry: .app(hit.app), best: hit.app))
            }
        }

        for folder in folders {
            let list = folderApps(folder)
            guard !list.isEmpty else { continue }
            let best = bestInFolder[folder.id]
            let nameMatch = SearchIndex.score(folderSearchEntry(folder.displayName), terms: terms)
            guard best != nil || nameMatch > 0 else { continue }

            let rank: SearchRank
            if let best, best.rank.match >= nameMatch {
                rank = SearchRank(match: best.rank.match, frecency: best.rank.frecency, name: folder.displayName)
            } else {
                let frecency = list.map { stats.score(for: $0.key, now: now) }.max() ?? 0
                rank = SearchRank(match: nameMatch, frecency: frecency, name: folder.displayName)
            }
            if list.count > 1 {
                candidates.append((rank: rank, entry: .folder(folder, list), best: best?.app))
            } else {
                candidates.append((rank: rank, entry: .app(list[0]), best: list[0]))   // single app left: shown as the app
            }
        }

        return candidates.sorted { $0.rank < $1.rank }.map { (entry: $0.entry, best: $0.best) }
    }

    // Folder names are few but pinyin transforms are not free: cache entries by display name.
    private func folderSearchEntry(_ name: String) -> SearchIndex.Entry {
        if let cached = folderEntryCache[name] { return cached }
        let entry = SearchIndex.folderEntry(name: name)
        folderEntryCache[name] = entry
        return entry
    }

    // Layout position of a displayed entry (search results → drag source).
    func layoutLocation(of entry: GridEntry) -> (page: Int, index: Int)? {
        for (p, page) in layoutStore.layout.pages.enumerated() {
            for (i, item) in page.enumerated() {
                switch (entry, item) {
                case (.app(let app), .app(let key)) where app.key == key:
                    return (p, i)
                case (.folder(let shown, _), .folder(let folder)) where shown.id == folder.id:
                    return (p, i)
                default:
                    continue
                }
            }
        }
        return nil
    }

    // MARK: - Show / hide

    // Visible and focused (what toggle / gestures treat as "open").
    var isShown: Bool { panel.isVisible && panel.isKeyWindow && !isFadingOut }

    // Panel on screen (incl. fading / warm-up) or a cold-launch show waiting.
    // One-time launch guides wait until this is false.
    var isBusy: Bool { panel.isVisible || pendingReadyShow != nil }

    // Runs action once apps and wallpaper are loaded (immediately if already ready).
    func showWhenReady(_ action: @escaping () -> Void) {
        if isReady {
            action()
        } else {
            pendingReadyShow = action
        }
    }

    // Drops a waiting cold-launch show; true if one was pending.
    @discardableResult
    func cancelPendingShow() -> Bool {
        guard pendingReadyShow != nil else { return false }
        pendingReadyShow = nil
        return true
    }

    // A Dock click can close the panel (resign key) just before the reopen event arrives;
    // the Dock toggle treats that as "was open".
    var didJustCloseFromOutsideClick: Bool {
        ProcessInfo.processInfo.systemUptime - lastOutsideClose < 0.5
    }

    func toggle() {
        if isShown {
            hide()
        } else {
            show()
        }
    }

    // Next panel shows opaque on top, then this one closes (no flash).
    func beginHandOff() {
        PanelSwitch.begin(from: panel) { [weak self] in self?.hide() }
    }

    // Non-activating panel: becomes key without activating AppPad.
    func show() {
        cancelTransition()
        let handOff = PanelSwitch.prepareIncoming(panel)
        guard presentPanel(opaque: handOff) else { return }
        if handOff {
            // ⌘⇧J/K switch: opaque over / morphing from the previous panel; input switch after its hide().
            viewController.focusSearch()
            PanelSwitch.takeOver(panel) { [weak self] in self?.switchInputIfNeeded() }
            return
        }
        finishShow()
        animateIn()
    }

    // Fade in + icons settle from slightly larger (same look as the pinch open).
    private func animateIn() {
        setContentScale(scale(forVisibility: 0), duration: nil)
        // Commit the first frame first, so the fade doesn't run during backing-store setup.
        container.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
        let token = transitionToken
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.transitionToken, self.panel.isVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.showDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
                self.setContentScale(1, duration: Self.showDuration)
            }
        }
    }

    // animated: fade out + icons grow, then order out. A show() meanwhile cancels it.
    func hide(animated: Bool = false, duration: TimeInterval? = nil) {
        guard panel.isVisible, !isHiding else { return }
        guard animated else {
            hideNow()
            return
        }
        guard !isFadingOut else { return }
        cancelTransition()
        isFadingOut = true
        panel.ignoresMouseEvents = true
        PinchGestureMonitor.shared.setTapEnabled(false)
        let token = transitionToken
        let length = duration ?? Self.hideDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = length
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().alphaValue = 0
            self.setContentScale(self.scale(forVisibility: 0), duration: length, timing: .easeIn)
        } completionHandler: { [weak self] in
            guard let self, token == self.transitionToken else { return }
            self.hideNow()
        }
    }

    private func hideNow() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        cancelTransition()
        isFadingOut = false
        panel.orderOut(nil)
        panel.ignoresMouseEvents = false
        PinchGestureMonitor.shared.setTapEnabled(false)
        setContentScale(1, duration: nil)
        viewController.didHide()
        InputSourceSwitcher.restore()   // no-op unless we switched on show
        isHiding = false
    }

    // Frame + content ready, ordered in at alpha 0 (opaque: panel switch hand-over, opaque or morphing).
    @discardableResult
    private func presentPanel(opaque: Bool = false) -> Bool {
        // An app-modal alert is up: the full-screen panel would cover it while the modal
        // session blocks every click on the panel → nothing clickable.
        guard NSApp.modalWindow == nil else { return false }
        guard let screen = PanelScreen.target() else { return false }
        endWarmUp(orderOut: false)
        // Interrupts an animated hide.
        isFadingOut = false
        panel.ignoresMouseEvents = false
        applyAppearance()
        applyFrame(targetFrame(on: screen), on: screen, display: false)
        viewController.prepareForShow(resetToFirstPage: prefs.openPagePolicy == .firstPage)
        setContentScale(1, duration: nil)
        panel.alphaValue = opaque ? PanelSwitch.incomingAlpha(for: panel) : 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        spaceGuard?.panelDidShow()
        PinchGestureMonitor.shared.setTapEnabled(true)
        return true
    }

    // A tap that stopped a page swipe never becomes a click (macOS eats it).
    // Replay it as a click, only on empty space, so "tap outside closes" works mid-swipe.
    // Also while a pinch open is running or just finished: a tap there cancels (closes) it.
    private func handleTrackpadTap() {
        guard panel.isVisible, panel.isKeyWindow, !isFadingOut, TapToClick.isEnabled else { return }
        // Drag / drop landing or just committed: a synthesized click could hit stale empty space.
        guard !viewController.isDropSettling else { return }
        // Only the first tap after a pinch gets eaten; once a real click arrived, stop replaying.
        let pinchOpening = transition == .opening
            || (ProcessInfo.processInfo.systemUptime - lastPinchOpen < Self.pinchTapWindow
                && panel.lastRealMouseDown < pinchOpenBegan)
        guard pinchOpening || (transition == nil && PagerView.isScrollActive) else { return }
        let point = panel.mouseLocationOutsideOfEventStream
        guard let content = panel.contentView,
              content.bounds.contains(content.convert(point, from: nil)),
              viewController.isEmptySpace(atWindowPoint: point)
        else { return }
        CloseLog.note("launchpad: replay tap (pinch: \(pinchOpening))")
        panel.replayClick(atWindowPoint: point)
    }

    // Input source + search focus, once the panel is really open.
    private func finishShow() {
        switchInputIfNeeded()
        viewController.focusSearch()
    }

    private func switchInputIfNeeded() {
        if prefs.switchToEnglishInput { InputSourceSwitcher.switchToASCII() }
    }

    // MARK: - Interactive pinch transition (macOS 15 Launchpad style)

    nonisolated private enum TransitionMode: Equatable { case opening, closing }
    private var transition: TransitionMode?
    private var transitionProgress: CGFloat = 0
    private var transitionToken = 0   // invalidates stale finish animations
    // Last pinch-open activity: macOS eats taps right after a system gesture, so they are replayed.
    private var lastPinchOpen: TimeInterval = -1
    // Start of the last pinch open (real clicks after it end the tap-replay window).
    private var pinchOpenBegan: TimeInterval = -1
    private static let pinchTapWindow: TimeInterval = 1.0

    // Icons start this much larger and settle to 1× as the panel fades in.
    private static let pinchZoom: CGFloat = 0.12

    func beginInteractiveOpen() {
        guard transition == nil, !isShown, presentPanel() else { return }
        transitionToken += 1
        transition = .opening
        transitionProgress = 0
        lastPinchOpen = ProcessInfo.processInfo.systemUptime
        pinchOpenBegan = lastPinchOpen
        applyVisibility(0)
    }

    func beginInteractiveClose() {
        guard transition == nil, isShown else { return }
        transitionToken += 1
        transition = .closing
        transitionProgress = 0
        applyVisibility(1)
    }

    func updateInteractive(progress: CGFloat) {
        guard let transition else { return }
        transitionProgress = progress
        applyVisibility(transition == .opening ? progress : 1 - progress)
    }

    // Fingers lifted: finish or roll back depending on progress and flick velocity.
    func endInteractive(velocity: CGFloat) {
        guard let mode = transition else { return }
        transition = nil
        let complete = velocity > 1.5 || (velocity > -1.5 && transitionProgress > 0.35)
        let open = (mode == .opening) == complete
        let visible = mode == .opening ? transitionProgress : 1 - transitionProgress
        let distance = abs((open ? 1 : 0) - visible)
        let duration = max(0.08, 0.25 * Double(distance))
        if mode == .opening { lastPinchOpen = ProcessInfo.processInfo.systemUptime + duration }

        transitionToken += 1
        let token = transitionToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().alphaValue = open ? 1 : 0
            self.setContentScale(self.scale(forVisibility: open ? 1 : 0), duration: duration)
        } completionHandler: { [weak self] in
            guard let self, token == self.transitionToken else { return }
            if !open {
                self.hide()
            } else if mode == .opening {
                self.finishShow()   // a cancelled close is already set up
            }
        }
    }

    // Any other show/hide path wins over a gesture in flight.
    private func cancelTransition() {
        transition = nil
        transitionToken += 1
    }

    private func applyVisibility(_ visibility: CGFloat) {
        let v = min(max(visibility, 0), 1)
        panel.alphaValue = v
        setContentScale(scale(forVisibility: v), duration: nil)
    }

    private func scale(forVisibility visibility: CGFloat) -> CGFloat {
        1 + Self.pinchZoom * (1 - visibility)
    }

    // Scales the icon layer (not the wallpaper) around its center.
    private func setContentScale(_ scale: CGFloat, duration: TimeInterval?,
                                 timing: CAMediaTimingFunctionName = .easeOut) {
        guard let layer = viewController.view.layer else { return }
        let size = layer.bounds.size
        let dx = (0.5 - layer.anchorPoint.x) * size.width
        let dy = (0.5 - layer.anchorPoint.y) * size.height
        var target = CATransform3DMakeTranslation(dx, dy, 0)
        target = CATransform3DScale(target, scale, scale, 1)
        target = CATransform3DTranslate(target, -dx, -dy, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            animation.toValue = NSValue(caTransform3D: target)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: timing)
            layer.add(animation, forKey: "launchpadZoom")
        } else {
            layer.removeAnimation(forKey: "launchpadZoom")
        }
        layer.transform = target
        CATransaction.commit()
    }

    // Click outside the panel → close.
    func windowDidResignKey(_ notification: Notification) {
        guard !PanelSwitch.isOutgoing(panel) else { return }   // next panel took key
        if panel.isVisible, !isHiding, !isFadingOut {
            lastOutsideClose = ProcessInfo.processInfo.systemUptime
            let keyWindow = NSApp.keyWindow?.className ?? "none"
            CloseLog.note("launchpad: resigned key (key window: \(keyWindow))")
        }
        hide(animated: true)
    }

    // Light / dark labels from the composed background brightness (style, theme, opacity, wallpaper).
    private func applyAppearance() {
        let screen = panel.isVisible ? panel.screen : PanelScreen.target()
        panel.appearance = PanelBackgroundSpec.current(for: .launchpad).appearance(on: screen)
    }

    // 100% of the screen + "Cover the menu bar": the area grows up to the screen's top edge.
    private var coversMenuBar: Bool {
        prefs.windowPercent >= 100 && prefs.launchpadCoversMenuBar
    }

    // Area the panel is sized / centered in.
    private func availableFrame(on screen: NSScreen) -> NSRect {
        var area = screen.visibleFrame
        if coversMenuBar { area.size.height = screen.frame.maxY - area.minY }
        return area
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let visible = availableFrame(on: screen)
        let ratio = CGFloat(min(max(prefs.windowPercent, 30), 100)) / 100
        // Slightly taller than wide (+6%, capped at 100%) so rows are not cramped,
        // unless all three panels use the same percent (then they line up exactly).
        let heightRatio = prefs.launchpadMatchesPanels ? ratio : min(ratio + 0.06, 1)
        var size = NSSize(width: visible.width * ratio, height: visible.height * heightRatio)
        size.width = min(max(size.width, 480), visible.width)
        size.height = min(max(size.height, 360), visible.height)
        return NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    // Sets frame, corner radius, shadow and wallpaper slice together.
    private func applyFrame(_ frame: NSRect, on screen: NSScreen, display: Bool) {
        // Above the menu bar only while actually reaching into it (that level also covers the Dock).
        panel.level = frame.maxY > screen.visibleFrame.maxY + 0.5 ? LaunchpadPanel.aboveMenuBarLevel : .floating
        panel.setFrame(frame, display: display)
        let visible = availableFrame(on: screen)
        let filled = frame.width >= visible.width - 1 && frame.height >= visible.height - 1
        let radius = filled ? Self.filledCornerRadius : Self.cornerRadius
        container.layer?.cornerRadius = radius
        viewController.root.layer?.cornerRadius = radius
        panel.cornerMaskRadius = radius
        // Notched screen: keep the search field clear of the camera housing when reaching the top.
        let topGap = screen.frame.maxY - frame.maxY
        viewController.topInset = max(0, screen.safeAreaInsets.top - topGap)
        viewController.fillsScreen = filled
        // No shadow when filled: it would spill onto the menu bar and Dock.
        panel.dropsShadow = !filled
        let spec = PanelBackgroundSpec.current(for: .launchpad)
        background.update(spec: spec, screen: screen, panelFrame: frame)
        panel.appearance = spec.appearance(on: screen)
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        // ⌘⇧J / ⌘⇧K: previous / next panel.
        if flags == [.command, .shift], key == "j" || key == "k" {
            beginHandOff()
            onSwitchPanel?(key == "j" ? -1 : 1)
            return true
        }
        guard flags == .command else { return false }
        switch key {
        case "w":
            hide()
            return true
        case ",":
            // Same slow fade as a click on empty space; Settings opens underneath meanwhile.
            hide(animated: true, duration: Self.backgroundClickHideDuration)
            onOpenSettings?()
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    func launch(_ app: AppInfo) {
        let key = app.key
        CloseLog.note("launchpad: launch \(key)")
        stats.record(app.key, manual: true)
        hide()
        AppActivator.open(app.url)
    }

    func requestShortcut(for app: AppInfo) {
        hide()
        onRequestShortcut?(app)
    }

    func moveItem(from source: DragSource, to target: DropTarget) {
        layoutStore.move(from: source, to: target, capacity: capacity) { [appsByKey] targetKey, draggedKey in
            DefaultLayout.folderName(for: [targetKey, draggedKey].compactMap { appsByKey[$0] })
        }
        viewController.reloadAll()
    }

    func renameFolder(id: String, name: String) {
        layoutStore.renameFolder(id: id, to: name)
        viewController.reloadAll(refreshFolder: false)
    }

    var installedBundleIDs: Set<String> { Set(apps.compactMap(\.bundleID)) }

    func uninstall(_ app: AppInfo, bundleIDs: [String], extra: [URL]) async -> AppUninstaller.Result {
        let result = await AppUninstaller.uninstall(app, bundleIDs: bundleIDs, extra: extra)
        guard result.appRemoved else { return result }
        layoutStore.remove(appKey: app.key, capacity: capacity)
        apps.removeAll { $0.key == app.key }
        appsByKey[app.key] = nil
        viewController.reloadAll()
        return result
    }

    func applyPreferences() {
        if capacity != lastCapacity {
            lastCapacity = capacity
            layoutStore.reflow(capacity: capacity)
        }
        applyAppearance()
        viewController.reloadAll()
        if panel.isVisible, let screen = panel.screen {
            applyFrame(targetFrame(on: screen), on: screen, display: true)
            panel.invalidateShadow()
        }
    }

    // MARK: - Backup

    var currentLayout: Layout { layoutStore.layout }

    // Replaces pages / folders with a backup (grid size is set by the caller first).
    func restoreLayout(_ layout: Layout) {
        lastCapacity = capacity   // pending applyPreferences must not reflow it again
        layoutStore.restore(layout, apps: apps, capacity: capacity)
        viewController.reloadAll()
    }

    func confirmResetLayout() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset layout?")
        alert.informativeText = String(localized: "All pages and folders will be rearranged in the default order.")
        alert.addButton(withTitle: String(localized: "Reset"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        layoutStore.reset(apps: apps, capacity: capacity)
        viewController.reloadAll()
    }
}

// System "Tap to click" (built-in or Magic Trackpad). Without it a tap is never a click,
// so nothing should be replayed.
private enum TapToClick {
    static var isEnabled: Bool {
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        if domains.contains(where: { UserDefaults(suiteName: $0)?.bool(forKey: "Clicking") == true }) { return true }
        let global = CFPreferencesCopyValue("com.apple.mouse.tapBehavior" as CFString, kCFPreferencesAnyApplication,
                                            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return (global as? Int) == 1
    }
}

// Search order: match quality, then frecency, then name ("<" = shown first).
nonisolated private struct SearchRank: Comparable {
    let match: Int
    let frecency: Double
    let name: String

    static func < (a: SearchRank, b: SearchRank) -> Bool {
        if a.match != b.match { return a.match > b.match }
        if a.frecency != b.frecency { return a.frecency > b.frecency }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
