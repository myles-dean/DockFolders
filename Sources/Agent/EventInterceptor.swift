import AppKit

/// A Quartz event tap that catches clicks on folder tiles in the Dock before the Dock sees them.
///
/// • Click a folder tile      → open its popup (the Dock never launches the stub).
/// • Drag a folder tile       → replayed to the Dock, so tiles can still be rearranged.
/// • Right-click a folder     → our folder menu.
/// • Drag an app's tile        → watched (not changed), so it can be dropped onto a folder.
/// • Click anywhere else while a popup is open → close it.
final class EventInterceptor {
    static let shared = EventInterceptor()

    // Main-thread callbacks.
    var onFolderClick: ((String, DockItem) -> Void)?
    var onFolderMenu: ((String, DockItem) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onMenuOutsideClick: (() -> Void)?
    var onOverviewPanelClick: ((String, CGPoint, CGPoint) -> Void)?
    /// Dragging an app's tile (the Dock does the dragging; we only watch). Points are global, top-left origin.
    var onAppDragBegan: ((DockItem) -> Void)?
    var onAppDragMoved: ((CGPoint) -> Void)?
    var onAppDragEnded: ((CGPoint) -> Void)?

    private let replayMarker: Int64 = 0x44_46_4F_4C // "DFOL"
    private var tap: CFMachPort?

    // Shared with the tap thread.
    private let lock = NSLock()
    private var stubPaths: [String: String] = [:]   // normalised stub path → folder id
    private var panelFrame: CGRect?                  // global, top-left origin
    private var overviewPanel: (folderID: String, frame: CGRect)?
    private var menuFrames: [CGRect] = []            // open glass menus, same space
    private var screenFrames: [CGRect] = []          // global, top-left origin

    // Tap-thread only.
    private var pending: (event: CGEvent, folderID: String, item: DockItem, start: CGPoint)?
    private var swallowLeftUp = false
    private var swallowRightUp = false
    private var overviewPress: (folderID: String, start: CGPoint, dragged: Bool)?
    private var appDrag: (item: DockItem, start: CGPoint, active: Bool)?

    var isRunning: Bool { tap != nil }

    // MARK: State updates (main thread)

    func update(folders: [Folder]) {
        var map: [String: String] = [:]
        for folder in folders {
            map[folder.stubURL.standardizedFileURL.resolvingSymlinksInPath().path] = folder.id
            // A renamed folder's tile points at its old stub until the Dock restarts.
            map[FolderActions.dockURL(for: folder).standardizedFileURL.resolvingSymlinksInPath().path] = folder.id
        }
        lock.withLock { stubPaths = map }
    }

    func setPanelFrame(_ frame: CGRect?, overviewFolderID: String? = nil, overviewBody: CGRect = .zero) {
        lock.withLock {
            panelFrame = frame
            overviewPanel = overviewFolderID.map { ($0, overviewBody) }
        }
    }
    func setMenuFrames(_ frames: [CGRect]) { lock.withLock { menuFrames = frames } }

    func updateScreens() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frames = NSScreen.screens.map { s in
            CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        lock.withLock { screenFrames = frames }
    }

    // MARK: Tap lifecycle

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        updateScreens()
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<EventInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Dock Folders event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    // MARK: Event handling (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == replayMarker { return pass }

        let location = event.location

        // The overview takes mouse input even over a visible third-party panel. Claim a
        // primary click that begins in our popup and deliver it to the folder on mouse-up.
        if let press = overviewPress {
            switch type {
            case .leftMouseDragged:
                if hypot(location.x - press.start.x, location.y - press.start.y) > 5 { overviewPress?.dragged = true }
                return nil
            case .leftMouseUp:
                overviewPress = nil
                if !press.dragged { main { self.onOverviewPanelClick?(press.folderID, press.start, location) } }
                return nil
            case .leftMouseDown:
                overviewPress = nil
            default: break
            }
        }

        // An app's tile being dragged: the Dock owns the drag, wherever it goes (even over the
        // popup); we only watch it.
        if var drag = appDrag, type == .leftMouseDragged || type == .leftMouseUp {
            if type == .leftMouseUp {
                appDrag = nil
                if drag.active { main { self.onAppDragEnded?(location) } }
            } else {
                if !drag.active, hypot(location.x - drag.start.x, location.y - drag.start.y) > 5 {
                    drag.active = true
                    appDrag = drag
                    let item = drag.item
                    main { self.onAppDragBegan?(item) }
                }
                if drag.active { main { self.onAppDragMoved?(location) } }
            }
            return pass
        }

        let (panel, overview, menus) = lock.withLock { (panelFrame, overviewPanel, menuFrames) }

        // While one of our menus is open, a click outside it only dismisses it (like a real menu).
        if !menus.isEmpty {
            if menus.contains(where: { $0.contains(location) }) { return pass }
            switch type {
            case .leftMouseDown: swallowLeftUp = true; main { self.onMenuOutsideClick?() }; return nil
            case .rightMouseDown: swallowRightUp = true; main { self.onMenuOutsideClick?() }; return nil
            case .otherMouseDown: main { self.onMenuOutsideClick?() }; return nil
            default: break
            }
        }
        if type == .leftMouseUp, swallowLeftUp { swallowLeftUp = false; return nil }
        if type == .rightMouseUp, swallowRightUp { swallowRightUp = false; return nil }
        if type == .leftMouseDown, !event.flags.contains(.maskControl),
           let overview, overview.frame.contains(location) {
            overviewPress = (overview.folderID, location, false)
            return nil
        }
        if let panel, panel.contains(location) { return pass }   // clicks inside the popup

        switch type {
        case .leftMouseDown:
            appDrag = nil
            if nearDockEdge(location), let item = DockAX.shared.itemForOpening(at: location) {
                if let id = folderID(for: item) {
                    if event.flags.contains(.maskControl) {          // control-click = right-click
                        guard !DockAX.shared.overviewIsActive else { return pass }
                        swallowLeftUp = true
                        main { self.onFolderMenu?(id, item) }
                    } else if let copy = event.copy() {
                        pending = (copy, id, item, location)
                    }
                    return nil
                }
                if isPlainApp(item) { appDrag = (item, location, false) }
            }
            if panel != nil { main { self.onOutsideClick?() } }

        case .leftMouseDragged:
            if let p = pending {
                if hypot(location.x - p.start.x, location.y - p.start.y) > 5 {
                    // It's a drag: hand the original press and this drag to the Dock, and watch it
                    // like an app's (a folder can be dropped onto another folder to merge them).
                    pending = nil
                    p.event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
                    p.event.post(tap: .cgSessionEventTap)
                    if let drag = event.copy() {
                        drag.setIntegerValueField(.eventSourceUserData, value: replayMarker)
                        drag.post(tap: .cgSessionEventTap)
                    }
                    appDrag = (p.item, p.start, true)
                    let item = p.item
                    main { self.onAppDragBegan?(item) }
                }
                return nil
            }

        case .leftMouseUp:
            if let p = pending {
                pending = nil
                main { self.onFolderClick?(p.folderID, p.item) }
                return nil
            }

        case .rightMouseDown:
            if let (id, item) = folderHit(at: location), !DockAX.shared.overviewIsActive {
                swallowRightUp = true
                main { self.onFolderMenu?(id, item) }
                return nil
            }
            if panel != nil { main { self.onOutsideClick?() } }

        case .otherMouseDown:
            if panel != nil { main { self.onOutsideClick?() } }

        default:
            break
        }
        return pass
    }

    /// Cheap check before asking the Dock: is the point near a screen edge the Dock could be on?
    private func nearDockEdge(_ p: CGPoint) -> Bool {
        let band: CGFloat = 220
        let screens = lock.withLock { screenFrames }
        for s in screens where s.contains(p) {
            switch CoreDock.orientation {
            case .bottom: return p.y > s.maxY - band
            case .left: return p.x < s.minX + band
            case .right: return p.x > s.maxX - band
            }
        }
        return false
    }

    private func folderHit(at p: CGPoint) -> (String, DockItem)? {
        guard nearDockEdge(p), let item = DockAX.shared.item(at: p), let id = folderID(for: item) else { return nil }
        return (id, item)
    }

    private func folderID(for item: DockItem) -> String? {
        guard let url = item.url else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return lock.withLock { stubPaths[path] }
    }

    /// An ordinary app's tile (not a folder, Finder, the Apps launcher, a stack or the Trash).
    private func isPlainApp(_ item: DockItem) -> Bool {
        guard item.subrole == "AXApplicationDockItem", let url = item.url, url.pathExtension == "app" else { return false }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        if bundleID == "com.apple.finder" || bundleID == "com.apple.apps.launcher" { return false }
        return folderID(for: item) == nil
    }

    private func main(_ block: @escaping () -> Void) { DispatchQueue.main.async(execute: block) }
}
