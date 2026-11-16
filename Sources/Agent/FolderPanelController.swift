import AppKit
import QuartzCore

import SwiftUI

/// A borderless, non-activating panel: clicking it never steals focus from your current app.
final class FolderPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        // After isFloatingPanel (which resets the level). Must sit above the Dock's window (level 20).
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    // Never actually key (the Dock keeps keyboard focus so it stays on screen), but drawn as if it
    // were: Liquid Glass "recedes" in windows that aren't focused, flattening its edges.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var isKeyWindow: Bool { true }
}

/// Shows a folder's popup above its Dock tile and behaves like the Dock's own name label:
/// it rides on the tile as it magnifies, keeps the Dock up while you're in it, and goes away
/// (letting an auto-hiding Dock hide) once you've moved off it for a moment.
final class FolderPanelController: NSObject {
    static let shared = FolderPanelController()

    private let model = FolderPanelModel()
    private lazy var panel: FolderPanel = {
        let panel = FolderPanel()
        let host = NSHostingView(rootView: FolderPanelView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    private(set) var folderID: String?
    private var holdingDock = false
    private var observers: [NSObjectProtocol] = []
    private var runningObserver: NSObjectProtocol?
    private var displayLink: CADisplayLink?
    private var frameCount = 0

    /// The folder's Dock tile, and its latest (possibly magnified) frame in AX coordinates.
    private var tileItem: DockItem?
    private var tileFrame: CGRect = .zero
    /// The Dock bar (AX list) frame, in Cocoa coordinates; refreshed a few times a second.
    private var barFrame: CGRect = .zero
    /// Where the popup currently is (Cocoa): glass including its pointer, and the body alone.
    private var popupFrame: CGRect = .zero
    private var bodyFrame: CGRect = .zero

    /// Resting width of one Dock tile (icon + spacing), measured when the popup opens.
    private var dockPitch: CGFloat?
    /// Tracks time outside the popup, folder tile and protected interaction areas.
    private var leaveTimer = FolderLeaveTimer()
    /// Until this time, losing the Dock's focus (e.g. hiding the frontmost app activated another
    /// one) re-holds the Dock instead of closing the popup.
    private var keepOpenUntil = Date.distantPast

    // Swipe paging state.
    private var scrollMonitor: Any?
    private var swiping = false
    private var swipeTranslation: CGFloat = 0
    private var swipeSamples: [(time: TimeInterval, dx: CGFloat)] = []
    private var lastWheelStep = Date.distantPast

    var isOpen: Bool { folderID != nil }

    /// Sprung open by an app dragged from the Dock: stays open until that drag ends.
    var heldForDrop = false
    /// Opened by resting the pointer on its tile (Settings → Open folders on hover).
    var openedByHover = false
    /// After an app was dropped in: stays open (and holds the Dock) a moment so you see it land.
    private var showLandedUntil = Date.distantPast

    private override init() {
        super.init()
        model.onOpen = { [weak self] app in self?.launch(app) }
        model.onSelectPage = { [weak self] page in self?.go(toPage: page) }
        model.onDragBegin = { [weak self] app, point in self?.beginDrag(app, at: point) }
        model.onDragEnd = { [weak self] in self?.endDrag() }
        model.onMenu = { [weak self] app, point in
            guard let self, let folderID = self.folderID else { return }
            GlassMenuController.shared.show(AppMenu.entries(for: app, folderID: folderID), at: point)
        }
    }

    // MARK: Showing

    func toggle(folderID: String, item: DockItem?) {
        FolderHover.shared.noteOpened(folderID)
        if self.folderID == folderID {
            // With hover opening, it's usually open already by the time you click: keep it.
            if FolderPrefs.opensOnHover { openedByHover = false } else { close() }
            return
        }
        show(folderID: folderID, item: item, pointerInitiated: true)
    }

    func show(folderID: String, item: DockItem?, pointerInitiated: Bool = false) {
        guard let folder = FolderStore.shared.folder(id: folderID),
              let item = item ?? DockAX.shared.item(for: FolderActions.dockURL(for: folder)) else { return }
        if isOpen { close(animated: false) }
        stopFollowingTile()
        // Clicking a Dock icon closes any Dock menu that's open; so does opening a folder.
        DockAX.shared.dismissMenus()

        self.folderID = folderID
        dockPitch = DockAX.shared.restingPitch()
        let apps = Self.apps(in: folder)
        model.metrics = metrics(for: apps.count, folderName: folder.name)
        model.labelWidth = DockLabel.width(for: folder.name)
        model.labelUnderneath = true   // opened from its tile: the Dock is showing its name
        model.apps = apps
        model.page = 0
        model.stripOffset = 0
        model.pointer = nil
        model.magnificationAmount = 0
        model.hovering = false
        model.hoverPoint = nil
        model.dragging = nil
        model.dragLifted = false
        model.dragOutside = false
        model.dropTargeted = false
        outsideDrag = nil
        landing = false
        leaveTimer = FolderLeaveTimer(pointerInitiated: pointerInitiated)
        openedByHover = false

        tileItem = item
        tileFrame = item.frame
        refreshBarFrame()
        // Opened without the pointer on the Dock (e.g. from the stub): hold it right away.
        if CoreDock.autoHideEnabled, !isOverDock(NSEvent.mouseLocation) { holdDock() }

        position()
        model.isPresented = false
        panel.level = .popUpMenu
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { self.model.isPresented = true }
        }
        startWatching()
    }

    /// Re-reads the open folder (after apps were added/removed or launched/quit).
    func reload() {
        guard let folderID else { return }
        guard let folder = FolderStore.shared.folder(id: folderID) else { close(); return }
        let apps = Self.apps(in: folder)
        let newMetrics = metrics(for: apps.count, folderName: folder.name)
        model.metrics = newMetrics
        model.apps = apps
        if model.page >= newMetrics.pages { model.page = newMetrics.pages - 1 }
        model.stripOffset = -CGFloat(model.page) * newMetrics.bodyWidth
        position()
    }

    // MARK: Closing

    /// Closes the popup if it's showing this folder (e.g. one being deleted).
    func close(ifShowing id: String) {
        if folderID == id { close() }
    }

    func close(animated: Bool = true) {
        guard isOpen else { return }
        heldForDrop = false
        // If the pointer isn't on an auto-hiding Dock, the Dock is (about to be) sliding away:
        // go with it, riding down on the tile and fading, rather than shrinking in place.
        let withDock = animated && CoreDock.autoHideEnabled && !isOverDock(NSEvent.mouseLocation)
        folderID = nil
        GlassMenuController.shared.closeAll()
        stopWatching(keepFollowingTile: withDock)
        EventInterceptor.shared.setPanelFrame(nil)

        if !animated {
            model.isPresented = false
            panel.orderOut(nil)
        } else if withDock {
            leavingUntil = Date().addingTimeInterval(0.28)
            withAnimation(.easeIn(duration: 0.22)) {
                model.isPresented = false
                model.magnificationAmount = 0
                model.hovering = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self, !self.isOpen else { return }
                self.stopFollowingTile()
                self.panel.orderOut(nil)
            }
        } else {
            withAnimation(.easeIn(duration: 0.13)) {
                model.isPresented = false
                model.pointer = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.isOpen else { return }
                self.panel.orderOut(nil)
            }
        }
        // An auto-hiding Dock slides away again (unless the pointer is on it).
        releaseDock()
    }

    private var leavingUntil: Date?

    private func stopFollowingTile() {
        leavingUntil = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Holding the Dock

    private func holdDock() {
        guard CoreDock.autoHideEnabled, !holdingDock else { return }
        holdingDock = DockAX.shared.holdOpen(selecting: tileItem)
    }

    private func releaseDock() {
        guard holdingDock else { return }
        holdingDock = false
        DockAX.shared.releaseHold()
    }

    /// Call before an action that may change the active app (Hide, Quit) but shouldn't close the folder.
    func stayOpenThroughAppSwitch() {
        keepOpenUntil = Date().addingTimeInterval(1.5)
    }

    private var inGracePeriod: Bool { Date() < keepOpenUntil }

    // MARK: Actions

    private func launch(_ app: FolderApp) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
        close()
    }

    // MARK: Every frame: follow the tile, track the pointer

    @objc private func tick(_ link: CADisplayLink) {
        // Leaving with the Dock: keep riding on the tile while the Dock slides away.
        if !isOpen {
            guard let until = leavingUntil, Date() < until, let tile = tileItem else { return }
            let frame = AX.frame(tile.element)
            if frame.width > 0 { tileFrame = frame; position() }
            return
        }
        frameCount += 1

        if let tile = tileItem {
            let frame = AX.frame(tile.element)
            if frame.width > 0 {
                tileFrame = frame
            } else if frameCount % 30 == 0, let folder = folderID.flatMap(FolderStore.shared.folder(id:)) {
                tileItem = DockAX.shared.item(for: FolderActions.dockURL(for: folder))   // the Dock restarted
            }
        }
        if frameCount % 10 == 0 { refreshBarFrame() }
        position()
        trackPointer()
    }

    private func trackPointer() {
        let mouse = NSEvent.mouseLocation
        let tile = cocoa(tileFrame)
        let menus = GlassMenuController.shared.isOpen
        let inMenu = GlassMenuController.shared.contains(mouse)
        let inPopup = popupFrame.insetBy(dx: -3, dy: -3).contains(mouse)
        let onTile = tile.insetBy(dx: -2, dy: -2).contains(mouse)
        let overDock = isOverDock(mouse)
        // Between the Dock and the popup, across the popup's width: on the way in or out.
        let approach = approachZone().contains(mouse)

        // The Dock draws its name labels in its own window, just below the popup. On the Dock over
        // another app, drop below that window so the app's name shows on top of the popup; anywhere
        // else (in the popup, a menu, or on the folder's own tile) stay above it, covering the
        // folder's own label.
        let level: NSWindow.Level = overDock && !onTile && !inMenu ? Self.belowDockLabels : .popUpMenu
        if panel.level != level { panel.level = level }

        // The Dock shows the folder's name label while the pointer is on its tile, and keeps it
        // up while an auto-hiding Dock is held open.
        let labelShowing = onTile || holdingDock
        if model.labelUnderneath != labelShowing { model.labelUnderneath = labelShowing }

        let dragging = model.dragging != nil || heldForDrop || Date() < showLandedUntil
        if model.dragging != nil { checkEdgeDwell() }
        updateMagnification(inside: inPopup && !menus && !dragging, mouse: mouse)

        // An auto-hiding Dock stays up by itself while the pointer is on it (and keeps
        // magnifying normally). Above it, in or on the way to the popup, hold it up.
        if CoreDock.autoHideEnabled {
            if overDock {
                releaseDock()
            } else if inPopup || approach || inMenu || dragging {
                holdDock()
            }
        }

        // One configurable timeout for every direction of departure and both opening methods.
        // Preserve the safe path between tile and popup, menus, drags and focus-change grace.
        if leaveTimer.shouldClose(pointerInside: inPopup || onTile,
                                  protected: approach || inMenu || menus || dragging || inGracePeriod,
                                  delay: FolderPrefs.closeDelay) {
            close()
            return
        }

        // Esc (or anything else) took the Dock's focus while we were holding it.
        if holdingDock, frameCount % 6 == 0, !DockAX.shared.isFocused {
            if inGracePeriod { holdingDock = DockAX.shared.holdOpen(selecting: tileItem); return }
            holdingDock = false
            if !overDock { close() }
        }
    }

    /// Like the Dock: magnification eases in when the pointer arrives and out when it leaves,
    /// and follows the pointer smoothly in between. Updated every frame, never animated.
    private func updateMagnification(inside: Bool, mouse: CGPoint) {
        let actual = CGPoint(x: mouse.x - bodyFrame.minX, y: bodyFrame.maxY - mouse.y)
        var pointer = model.pointer
        if inside {
            if let current = pointer, model.magnificationAmount > 0.05 {
                pointer = CGPoint(x: current.x + (actual.x - current.x) * 0.5, y: current.y + (actual.y - current.y) * 0.5)
            } else {
                pointer = actual
            }
        }
        var amount = model.magnificationAmount + ((inside ? 1 : 0) - model.magnificationAmount) * 0.22
        if abs(amount - (inside ? 1 : 0)) < 0.01 { amount = inside ? 1 : 0 }
        if amount == 0 { pointer = nil }

        let hoverPoint = inside ? actual : nil
        guard pointer != model.pointer || amount != model.magnificationAmount || inside != model.hovering
                || hoverPoint != model.hoverPoint else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.pointer = pointer
            model.magnificationAmount = amount
            model.hovering = inside
            model.hoverPoint = hoverPoint
        }
    }

    private func isOverDock(_ point: CGPoint) -> Bool {
        guard barFrame.width > 0 else { return false }
        switch CoreDock.orientation {
        case .bottom: return point.y <= barFrame.maxY && point.x >= barFrame.minX && point.x <= barFrame.maxX
        case .left: return point.x <= barFrame.maxX && point.y >= barFrame.minY && point.y <= barFrame.maxY
        case .right: return point.x >= barFrame.minX && point.y >= barFrame.minY && point.y <= barFrame.maxY
        }
    }

    /// Just under the Dock's window (which holds its icons and name labels).
    private static let belowDockLabels = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    private func approachZone() -> CGRect {
        switch CoreDock.orientation {
        case .bottom:
            return CGRect(x: popupFrame.minX - 16, y: barFrame.maxY - 2,
                          width: popupFrame.width + 32, height: max(0, popupFrame.minY - barFrame.maxY) + 6)
        case .left:
            return CGRect(x: barFrame.maxX - 2, y: popupFrame.minY - 16,
                          width: max(0, popupFrame.minX - barFrame.maxX) + 6, height: popupFrame.height + 32)
        case .right:
            return CGRect(x: popupFrame.maxX - 4, y: popupFrame.minY - 16,
                          width: max(0, barFrame.minX - popupFrame.maxX) + 6, height: popupFrame.height + 32)
        }
    }

    private func refreshBarFrame() {
        if let list = DockAX.shared.list { barFrame = cocoa(AX.frame(list)) }
    }

    // MARK: Rearranging (press and drag an icon)

    /// Where the pointer sits within the dragged icon, so it doesn't jump to the cursor.
    private var dragGrab: CGSize = .zero
    private var dragMonitor: Any?
    private var lastDragPoint: CGPoint?
    private var edgeDwellSince: Date?
    private var edgeDwellDirection = 0
    private var lastEdgeFlip = Date.distantPast

    private func bodyPoint(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: screen.x - bodyFrame.minX, y: bodyFrame.maxY - screen.y)
    }

    private func beginDrag(_ app: FolderApp, at screenPoint: CGPoint) {
        guard model.dragging == nil, !landing, let index = model.apps.firstIndex(where: { $0.id == app.id }) else { return }
        let point = bodyPoint(screenPoint)
        let center = model.metrics.iconCenter(index % model.metrics.perPage)
        dragGrab = CGSize(width: point.x - center.x, height: point.y - center.y)
        model.dragging = (app.id, center)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            model.dragLifted = true
            model.magnificationAmount = 0
        }
        // Follow the pointer from here on, wherever it goes (even past the popup's edges, or
        // after the icon has moved to another page).
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp {
                self.endDrag()
            } else {
                self.lastDragEvent = event
                self.moveDrag(to: NSEvent.mouseLocation)
            }
            return event
        }
        moveDrag(to: screenPoint)
    }

    private func moveDrag(to screenPoint: CGPoint) {
        guard let dragging = model.dragging else { return }
        lastDragPoint = screenPoint
        let m = model.metrics
        let pointer = bodyPoint(screenPoint)
        let location = CGPoint(x: pointer.x - dragGrab.width, y: pointer.y - dragGrab.height)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.dragging = (dragging.id, location) }

        // Carried well out of the folder: it becomes a real drag, which the Dock can take.
        if isFarOutside(pointer) {
            handOffToSystemDrag()
            return
        }

        // Pushed against (or past) the folder's left or right edge: flip pages, like iOS.
        let direction = pointer.x < 4 ? -1 : (pointer.x > m.bodyWidth - 4 ? 1 : 0)
        if direction != edgeDwellDirection { edgeDwellDirection = direction; edgeDwellSince = direction == 0 ? nil : Date() }

        // Make room once the icon is clearly over a spot on this page (not while it's between two,
        // so the others don't jitter back and forth).
        guard let from = model.apps.firstIndex(where: { $0.id == dragging.id }), model.isSettled else { return }
        let pageStart = model.page * m.perPage
        let onThisPage = from >= pageStart && from < pageStart + m.perPage
        let slots = min(m.perPage, model.apps.count - pageStart + (onThisPage ? 0 : 1))
        guard slots > 0 else { return }
        func distance(_ slot: Int) -> CGFloat {
            let c = m.iconCenter(slot)
            return hypot(c.x - location.x, c.y - location.y)
        }
        guard let nearest = (0..<slots).min(by: { distance($0) < distance($1) }),
              distance(nearest) < m.pitch * 0.42 || !onThisPage else { return }
        let to = min(pageStart + nearest, model.apps.count - 1)
        guard to != from else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            let app = model.apps.remove(at: from)
            model.apps.insert(app, at: to)
        }
    }

    private func checkEdgeDwell() {
        guard model.dragging != nil, edgeDwellDirection != 0, let since = edgeDwellSince,
              Date().timeIntervalSince(since) > 0.35, Date().timeIntervalSince(lastEdgeFlip) > 0.75 else { return }
        let target = model.page + edgeDwellDirection
        guard target >= 0, target < model.metrics.pages else { return }
        lastEdgeFlip = Date()
        go(toPage: target)
        // Once the new page has settled, carry the icon onto it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self, let point = self.lastDragPoint else { return }
            self.moveDrag(to: point)
        }
    }

    // MARK: Dragging an app out of the folder

    private var lastDragEvent: NSEvent?
    /// An app carried out of the folder as a real drag, and the folder it came from.
    private var outsideDrag: (app: FolderApp, folderID: String)?
    /// Where that drag is (Cocoa screen coordinates).
    private var outsidePoint: CGPoint = .zero

    /// Past the folder's edge by more than a little (the sides allow room for pushing against
    /// the edge to turn the page; the Dock side hands over almost at once).
    private func isFarOutside(_ p: CGPoint) -> Bool {
        let m = model.metrics
        let sides: CGFloat = 44, other: CGFloat = 16, toDock: CGFloat = 6
        let left = CoreDock.orientation == .left ? toDock : sides
        let right = CoreDock.orientation == .right ? toDock : sides
        let bottom = CoreDock.orientation == .bottom ? toDock : other
        return p.x < -left || p.x > m.bodyWidth + right || p.y < -other || p.y > m.bodyHeight + bottom
    }

    /// Hands the dragged icon over to a real drag of the app (as a link: never a copy or a move of
    /// the app itself). Over the Dock, the Dock makes room and adds it where it's let go.
    private func handOffToSystemDrag() {
        guard let dragging = model.dragging, let event = lastDragEvent, let view = panel.contentView,
              let folderID, let app = model.apps.first(where: { $0.id == dragging.id }) else { return }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        edgeDwellDirection = 0
        edgeDwellSince = nil
        lastDragPoint = nil
        saveOrder()
        outsideDrag = (app, folderID)
        outsidePoint = NSEvent.mouseLocation
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.dragOutside = true }

        let size = model.metrics.iconSize * 1.12
        let p = view.convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: p.x - dragGrab.width, y: p.y + (view.isFlipped ? -dragGrab.height : dragGrab.height))
        let item = NSDraggingItem(pasteboardWriter: app.url as NSURL)
        item.setDraggingFrame(NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                              contents: app.icon)
        let session = view.beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    fileprivate func outsideDragMoved(to point: CGPoint) { outsidePoint = point }

    /// Only a link, and only over the Dock: dropped anywhere else, nothing happens.
    fileprivate var outsideDragOperations: NSDragOperation { isOverDock(outsidePoint) ? .link : [] }

    fileprivate func finishOutsideDrag(at point: CGPoint, operation: NSDragOperation) {
        guard let drag = outsideDrag else { return }
        outsideDrag = nil
        DockPrefs.noteDockEdited()   // dropped on the Dock: it adds the tile and saves that later
        let url = drag.app.url
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.dragOutside = false
            model.dragging = nil
            model.dragLifted = false
        }
        if !operation.isEmpty {
            // The Dock took it and made its tile right where it was let go.
            DockPrefs.noteLivePin(url, tile: DockPrefs.appTile(for: url))
            FolderActions.moveAppToDock(url, from: drag.folderID)
        } else if isOverDock(point) {
            // Let go on the Dock but it didn't take the drop: kept now if it's running, otherwise
            // added at the next quiet moment.
            FolderActions.moveAppToDock(url, from: drag.folderID)
        }
        // Anywhere else it has slid back into its spot.
    }

    // MARK: Drops from the Dock

    /// While an app dragged from the Dock is over this folder: shows it faintly where it will land
    /// (after the folder's other apps) and slides to that page. `nil` takes the preview away.
    func previewDrop(of url: URL?) { previewDrop(of: url.map { [$0] } ?? []) }

    /// The same for several apps at once (a whole folder dragged onto this one).
    func previewDrop(of urls: [URL]) {
        guard isOpen, let folderID, let folder = FolderStore.shared.folder(id: folderID) else { return }
        var apps = Self.apps(in: folder)
        for url in urls where !folder.apps.contains(url.path) && FileManager.default.fileExists(atPath: url.path)
            && !apps.contains(where: { $0.url.path == url.path }) {
            apps.append(FolderApp(url: url, name: Self.displayName(of: url),
                                  icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: false, isPreview: true))
        }
        let url = apps.first(where: \.isPreview)?.url
        let m = metrics(for: apps.count, folderName: folder.name)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            model.metrics = m
            model.apps = apps
        }
        position()
        let target: Int
        if let url, let index = apps.firstIndex(where: { $0.url.path == url.path }) {
            target = index / m.perPage
        } else {
            target = min(model.page, m.pages - 1)
        }
        guard target != model.page else { return }
        // A beat after it opens, so you see it slide over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isOpen else { return }
            self.go(toPage: target)
        }
    }

    /// An app was just dropped in: stay open a moment so you see it in its spot.
    func showDropLanded() {
        showLandedUntil = Date().addingTimeInterval(1.3)
    }

    /// Whether a point (Cocoa screen coordinates) is on the open popup.
    func popupContains(_ point: CGPoint) -> Bool {
        isOpen && popupFrame.insetBy(dx: -6, dy: -6).contains(point)
    }

    func setDropTargeted(_ targeted: Bool) {
        if model.dropTargeted != targeted { model.dropTargeted = targeted }
    }

    /// True while a dropped icon glides into its spot.
    private var landing = false

    private func endDrag() {
        guard let dragging = model.dragging, !landing else { return }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        edgeDwellDirection = 0
        edgeDwellSince = nil
        lastDragPoint = nil
        saveOrder()

        // Glide from wherever it was let go into its spot, settling back to normal size, then
        // hand over to the icon in the grid.
        var target = dragging.location
        if let index = model.apps.firstIndex(where: { $0.id == dragging.id }) {
            let slot = index - model.page * model.metrics.perPage
            if (0..<model.metrics.perPage).contains(slot) { target = model.metrics.iconCenter(slot) }
        }
        landing = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            model.dragging = (dragging.id, target)
            model.dragLifted = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.model.dragging = nil }
            self.landing = false
        }
    }

    /// Saves the folder's new order (the Dock icon's 2×2 preview follows it).
    private func saveOrder() {
        guard let folderID, let folder = FolderStore.shared.folder(id: folderID) else { return }
        let ordered = model.apps.map(\.url.path)
        let missing = folder.apps.filter { !ordered.contains($0) }   // apps not on disk keep their place at the end
        guard ordered + missing != folder.apps,
              let updated = FolderStore.shared.update(folderID, { $0.apps = ordered + missing }) else { return }
        StubManager.refreshTile(updated)
    }

    // MARK: Paging (two-finger swipe follows your fingers, then snaps like iOS)

    private func go(toPage page: Int) {
        let m = model.metrics
        let target = min(max(page, 0), m.pages - 1)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            model.page = target
            model.stripOffset = -CGFloat(target) * m.bodyWidth
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let m = model.metrics
        guard m.pages > 1, !GlassMenuController.shared.isOpen else { return }
        let width = m.bodyWidth

        // A classic mouse wheel: one notch, one page.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1, Date().timeIntervalSince(lastWheelStep) > 0.35 else { return }
            lastWheelStep = Date()
            go(toPage: model.page + (delta < 0 ? 1 : -1))
            return
        }
        // We animate the settle ourselves, so trackpad momentum is ignored.
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.contains(.began) {
            swiping = true
            swipeTranslation = 0
            swipeSamples.removeAll()
        }
        guard swiping else { return }

        if event.phase.contains(.began) || event.phase.contains(.changed) {
            let dx = event.scrollingDeltaX
            swipeTranslation += dx
            swipeSamples.append((event.timestamp, dx))
            if swipeSamples.count > 8 { swipeSamples.removeFirst() }

            // Follow the fingers, with rubber-banding past the first and last pages.
            let raw = -CGFloat(model.page) * width + swipeTranslation
            let lowest = -CGFloat(m.pages - 1) * width
            var offset = raw
            if raw > 0 { offset = raw * 0.3 } else if raw < lowest { offset = lowest + (raw - lowest) * 0.3 }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.stripOffset = offset }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swiping = false
            let recent = swipeSamples.filter { event.timestamp - $0.time < 0.1 }
            var velocity: CGFloat = 0
            if let first = recent.first, let last = recent.last, last.time > first.time {
                velocity = recent.map(\.dx).reduce(0, +) / CGFloat(last.time - first.time)
            }
            var target = model.page
            if swipeTranslation < -width * 0.2 || velocity < -300 { target += 1 }
            else if swipeTranslation > width * 0.2 || velocity > 300 { target -= 1 }
            go(toPage: target)
        }
    }

    // MARK: Geometry

    private func metrics(for count: Int, folderName: String) -> FolderMetrics {
        let dockIcon = DockGeometry.tileSize ?? (dockPitch.map { $0 - 4 } ?? 52)
        let dockGap = max((dockPitch ?? dockIcon + 4) - dockIcon, 2)
        // Icons at the size chosen in Settings (the Dock's by default), spaced in proportion.
        let icon = FolderPrefs.customIconSize ?? dockIcon
        let pitch = icon + dockGap * icon / dockIcon
        let magnification = FolderPrefs.magnificationScale
        let names = FolderPrefs.showsNames
        let pageSize = FolderPrefs.appsPerPage
        let probe = FolderMetrics(iconSize: icon, dockPitch: pitch, appCount: count,
                                  minBodyWidth: 0, magnification: magnification, showsNames: names, pageSize: pageSize)
        // Wide enough that the Dock's name label for this folder hides behind the straight part
        // of the popup's bottom edge.
        let minWidth = DockLabel.width(for: folderName) + probe.cornerRadius * 1.4
        return FolderMetrics(iconSize: icon, dockPitch: pitch, appCount: count,
                             minBodyWidth: minWidth, magnification: magnification, showsNames: names, pageSize: pageSize)
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func cocoa(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Puts the popup's pointer exactly where the Dock would put this tile's name label:
    /// just above the tile, riding up and down with magnification.
    private func position() {
        guard tileFrame.width > 0 else { return }
        let m = model.metrics
        let bodyW = m.bodyWidth, bodyH = m.bodyHeight
        let arrow = FolderMetrics.arrowHeight
        let tile = cocoa(tileFrame)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: tile.midX, y: tile.midY)) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.frame.insetBy(dx: 8, dy: 8)
        let inset = DockLabel.tipInset

        var glass: CGRect
        switch CoreDock.orientation {
        case .bottom:
            model.arrowEdge = .bottom
            let tipX = tile.midX, tipY = tile.maxY - inset
            let bodyX = min(max(tipX - bodyW / 2, bounds.minX), bounds.maxX - bodyW)
            setArrowPosition(tipX - bodyX)
            glass = CGRect(x: bodyX, y: tipY, width: bodyW, height: bodyH + arrow)
            bodyFrame = CGRect(x: bodyX, y: tipY + arrow, width: bodyW, height: bodyH)
        case .left:
            model.arrowEdge = .leading
            let tipX = tile.maxX - inset, tipY = tile.midY
            let bodyTop = min(max(tipY + bodyH / 2, bounds.minY + bodyH), bounds.maxY)
            setArrowPosition(bodyTop - tipY)
            glass = CGRect(x: tipX, y: bodyTop - bodyH, width: bodyW + arrow, height: bodyH)
            bodyFrame = CGRect(x: tipX + arrow, y: bodyTop - bodyH, width: bodyW, height: bodyH)
        case .right:
            model.arrowEdge = .trailing
            let tipX = tile.minX + inset, tipY = tile.midY
            let bodyTop = min(max(tipY + bodyH / 2, bounds.minY + bodyH), bounds.maxY)
            setArrowPosition(bodyTop - tipY)
            glass = CGRect(x: tipX - arrow - bodyW, y: bodyTop - bodyH, width: bodyW + arrow, height: bodyH)
            bodyFrame = CGRect(x: tipX - arrow - bodyW, y: bodyTop - bodyH, width: bodyW, height: bodyH)
        }
        popupFrame = glass

        // Snap to whole pixels so following the tile never makes the glass shimmer.
        let scale = screen.backingScaleFactor
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        glass.origin = CGPoint(x: snap(glass.minX), y: snap(glass.minY))
        bodyFrame.origin = CGPoint(x: snap(bodyFrame.minX), y: snap(bodyFrame.minY))
        popupFrame = glass
        let content = m.contentSize(arrowOnSide: CoreDock.orientation != .bottom)
        let frame = CGRect(x: glass.minX - FolderMetrics.marginH, y: glass.minY - FolderMetrics.marginBottom,
                           width: content.width, height: content.height)
        let visible = frame.intersection(bounds)
        let visibleContent = CGRect(x: visible.minX - frame.minX, y: frame.maxY - visible.maxY,
                                    width: visible.width, height: visible.height)
        if model.visibleContentBounds != visibleContent { model.visibleContentBounds = visibleContent }
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        guard isOpen else { return }
        EventInterceptor.shared.setPanelFrame(CGRect(x: glass.minX, y: primaryHeight - glass.maxY,
                                                     width: glass.width, height: glass.height))
    }

    private func setArrowPosition(_ value: CGFloat) {
        if abs(model.arrowPosition - value) > 0.25 { model.arrowPosition = value }
    }

    // MARK: Watching for reasons to close

    private func startWatching() {
        stopWatching()
        frameCount = 0
        let link = panel.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.handleScroll(event)
            return nil
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, !self.inGracePeriod else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.close() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
        // Apps launching and quitting: keep the running dots right.
        runningObserver = NotificationCenter.default.addObserver(forName: RunningApps.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshRunningState()
        }
    }

    private func stopWatching(keepFollowingTile: Bool = false) {
        if !keepFollowingTile {
            displayLink?.invalidate()
            displayLink = nil
        }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        swiping = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let runningObserver { NotificationCenter.default.removeObserver(runningObserver) }
        runningObserver = nil
    }

    private func refreshRunningState() {
        guard isOpen else { return }
        let running = Self.runningAppPaths()
        let updated = model.apps.map { app in
            var app = app
            app.isRunning = running.contains(app.url.standardizedFileURL.path)
            return app
        }
        if updated != model.apps { model.apps = updated }
    }

    // MARK: Data

    /// Bundle paths of running apps.
    static func runningAppPaths() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            app.isTerminated ? nil : app.bundleURL?.standardizedFileURL.path
        })
    }

    static func apps(in folder: Folder) -> [FolderApp] {
        let running = runningAppPaths()
        return folder.appURLs.compactMap { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return FolderApp(url: url, name: displayName(of: url),
                             icon: NSWorkspace.shared.icon(forFile: url.path),
                             isRunning: running.contains(url.standardizedFileURL.path))
        }
    }

    static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

extension FolderPanelController: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? outsideDragOperations : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        outsideDragMoved(to: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishOutsideDrag(at: screenPoint, operation: operation)
    }
}
