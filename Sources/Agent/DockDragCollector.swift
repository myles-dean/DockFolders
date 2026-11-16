import AppKit

/// Dragging an app's tile in the Dock (the Dock does the dragging; this only watches, through the
/// event tap):
///  • Hold it over a folder for a moment and the folder springs open (outlined); let go on the
///    folder or in it, and the app goes in.
///  • Hold it over another app and a "Create Folder" tag appears above that app, like the Dock's
///    own name tags; let go and the two become a folder, in their place.
///
/// Targets are where tiles are right now (the Dock slides them aside as you drag, opening a gap
/// under the pointer; a gap is never a target). A quick pass over a tile doesn't count either, so
/// rearranging the Dock works as usual.
final class DockDragCollector {
    static let shared = DockDragCollector()

    private enum Target: Equatable {
        case folder(String)
        case app(URL)
    }

    private struct Tile {
        let target: Target
        let frame: CGRect   // global, top-left origin
    }

    private var dragged: DockItem?
    /// When the dragged tile is a folder: its id (it can be dropped onto another folder to merge).
    private var draggedFolderID: String?
    private var lastPoint: CGPoint = .zero
    /// Folder and app tiles where they are now (refreshed many times a second).
    private var currentTiles: [Tile] = []
    private var lastRefresh = Date.distantPast
    private var hover: Target?
    private var hoverToken = 0
    /// The folder that sprang open for this drag.
    private var openFolderID: String?
    /// The app showing "Create Folder".
    private var armedApp: URL?
    /// While a dragged app rests on an open folder's tile: keeps the Dock from spring-loading it.
    private var springGuard: Timer?
    private var springNudge: CGFloat = 1

    /// How long to hold before a folder springs open (quick: it only opens the folder)…
    private static let folderHoldDelay: TimeInterval = 0.18
    /// …and before Create Folder appears over an app (longer, so passing over one on the way
    /// somewhere never makes a folder).
    private static let createFolderHoldDelay: TimeInterval = 0.5

    // MARK: Drag (from the event tap, on the main thread)

    func began(_ item: DockItem) {
        DockPrefs.noteDockEdited()   // the Dock may move or drop this tile, and saves that later
        dragged = item
        let path = item.url?.standardizedFileURL.resolvingSymlinksInPath().path
        draggedFolderID = FolderStore.shared.folders.first {
            FolderActions.dockURL(for: $0).standardizedFileURL.resolvingSymlinksInPath().path == path
        }?.id
        openFolderID = nil
        armedApp = nil
        hover = nil
        currentTiles = tiles(excluding: item.url)
        lastRefresh = Date()
    }

    func moved(to point: CGPoint) {
        guard let dragged else { return }
        lastPoint = point
        refreshTiles()
        let panel = FolderPanelController.shared
        if let open = openFolderID {
            panel.setDropTargeted(panel.folderID == open && (panel.popupContains(cocoa(point)) || target(at: point) == .folder(open)))
            return
        }
        var over = target(at: point)
        // A folder goes into folders, not onto apps.
        if draggedFolderID != nil, case .app? = over { over = nil }
        if let armed = armedApp, over == .app(armed) {
            if let frame = currentFrame(of: .app(armed)) { DockTag.shared.move(toTile: frame) }
            return
        }
        guard over != hover else { return }
        hover = over
        hoverToken += 1
        if armedApp != nil { armedApp = nil; DockTag.shared.hide() }
        guard let over else { return }
        // The Dock spring-loads a tile something rests on for half a second; keep that from
        // happening while we wait (and after).
        startSpringGuard()
        // Held there (even without moving): act on it.
        let token = hoverToken
        let delay: TimeInterval
        if case .app = over { delay = Self.createFolderHoldDelay } else { delay = Self.folderHoldDelay }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.dragged != nil, self.hoverToken == token else { return }
            // Still over that tile where it is now (not a gap it slid away from)?
            self.refreshTiles(force: true)
            guard self.target(at: self.lastPoint) == over else { return }
            switch over {
            case .folder(let id):
                self.openFolderID = id
                panel.show(folderID: id, item: nil)
                panel.heldForDrop = true
                panel.setDropTargeted(true)
                // Show where it will land (sliding to that page if the others are full): the app,
                // or every app of a folder being dragged in.
                if let source = self.draggedFolderID.flatMap(FolderStore.shared.folder(id:)) {
                    panel.previewDrop(of: source.appURLs)
                } else {
                    panel.previewDrop(of: self.dragged?.url)
                }
            case .app(let url):
                guard let frame = self.currentFrame(of: over) else { return }
                self.armedApp = url
                DockTag.shared.show(L10n.text("Create Folder"), forTile: frame)
            }
        }
    }

    func ended(at point: CGPoint) {
        DockPrefs.noteDockEdited()
        let panel = FolderPanelController.shared
        let url = dragged?.url
        let open = openFolderID
        let armed = armedApp
        let sourceFolder = draggedFolderID
        dragged = nil
        draggedFolderID = nil
        openFolderID = nil
        armedApp = nil
        hover = nil
        hoverToken += 1
        springGuard?.invalidate()
        springGuard = nil
        panel.heldForDrop = false
        panel.setDropTargeted(false)
        DockTag.shared.hide()
        guard let url else { return }

        if let open, panel.folderID == open {
            let inPopup = panel.popupContains(cocoa(point))
            guard inPopup || target(at: point) == .folder(open) else {
                panel.previewDrop(of: nil)   // let go elsewhere: the preview goes
                return
            }
            // The preview becomes the app (or the folder's apps), in the same spot; the folder stays
            // a moment to show it.
            if let sourceFolder {
                FolderActions.mergeFolder(sourceFolder, into: open)
            } else {
                FolderActions.dropFromDock(url, into: open, releasedOnDock: !inPopup)
            }
            panel.showDropLanded()
        } else if let armed, target(at: point) == .app(armed) {
            FolderActions.combineInDock(dragged: url, onto: armed)
        }
    }

    // MARK: Spring-loading

    /// Holding a dragged item on an app's Dock tile for half a second makes the Dock spring-load
    /// it (showing that app's windows to drop into). Other apps can't switch that off for the
    /// Dock alone, so while the drag rests on a folder's or app's tile, nudge the Dock's idea of the
    /// pointer by a point every 0.2 s (sent only to the Dock; the real pointer doesn't move, and
    /// the Dock drops under the real pointer), so it never counts as resting.
    private func startSpringGuard() {
        springGuard?.invalidate()
        springGuard = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            // Only while resting on the tile being held over (a sprung folder, or an app).
            guard let self, self.dragged != nil,
                  let resting = self.openFolderID.map({ Target.folder($0) }) ?? self.hover,
                  self.target(at: self.lastPoint) == resting,
                  let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
            self.springNudge = -self.springNudge
            let p = CGPoint(x: self.lastPoint.x + self.springNudge, y: self.lastPoint.y)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?
                .postToPid(dock.processIdentifier)
        }
    }

    // MARK: Where the tiles are

    private func refreshTiles(force: Bool = false) {
        guard let dragged, force || Date().timeIntervalSince(lastRefresh) > 0.05 else { return }
        currentTiles = tiles(excluding: dragged.url)
        lastRefresh = Date()
    }

    private func target(at point: CGPoint) -> Target? {
        // The middle of a tile where it is now (not its edges, where you'd aim to drop beside it).
        currentTiles.first { $0.frame.insetBy(dx: $0.frame.width * 0.2, dy: -8).contains(point) }?.target
    }

    private func currentFrame(of target: Target) -> CGRect? {
        currentTiles.first { $0.target == target }?.frame
    }

    /// Folders and ordinary apps in the Dock (not Finder, the Apps launcher, or the dragged app).
    private func tiles(excluding draggedURL: URL?) -> [Tile] {
        func path(_ url: URL?) -> String? { url?.standardizedFileURL.resolvingSymlinksInPath().path }
        let folders = Dictionary(FolderStore.shared.folders.compactMap { folder in
            path(FolderActions.dockURL(for: folder)).map { ($0, folder.id) }
        }, uniquingKeysWith: { first, _ in first })
        let skip = path(draggedURL)
        return DockAX.shared.items.compactMap { item in
            guard item.frame.width > 0, let url = item.url, let p = path(url), p != skip else { return nil }
            if let id = folders[p] { return Tile(target: .folder(id), frame: item.frame) }
            guard item.subrole == "AXApplicationDockItem", url.pathExtension == "app" else { return nil }
            let bundleID = Bundle(url: url)?.bundleIdentifier
            guard bundleID != "com.apple.finder", bundleID != "com.apple.apps.launcher" else { return nil }
            return Tile(target: .app(url), frame: item.frame)
        }
    }

    private func cocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }
}
