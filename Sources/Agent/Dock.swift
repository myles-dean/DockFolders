import AppKit

// MARK: - Private CoreDock calls (HIServices). Looked up at runtime so a missing symbol can't crash us.

enum CoreDock {
    private typealias GetBool = @convention(c) () -> Bool
    private typealias GetOrientation = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void

    private static let handle = dlopen(nil, RTLD_NOW)

    static var autoHideEnabled: Bool {
        guard let sym = dlsym(handle, "CoreDockGetAutoHideEnabled") else { return false }
        return unsafeBitCast(sym, to: GetBool.self)()
    }

    enum Orientation { case bottom, left, right }

    static var orientation: Orientation {
        guard let sym = dlsym(handle, "CoreDockGetOrientationAndPinning") else { return .bottom }
        var orientation: Int32 = 0, pinning: Int32 = 0
        unsafeBitCast(sym, to: GetOrientation.self)(&orientation, &pinning)
        switch orientation {
        case 3: return .left
        case 4: return .right
        default: return .bottom
        }
    }
}

enum DockGeometry {
    private static func pref(_ key: String) -> Any? {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        return CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString)
    }

    /// The Dock's icon size setting ("Size" in Desktop & Dock), in points.
    static var tileSize: CGFloat? {
        (pref("tilesize") as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    /// Share of the Dock's magnification used inside folders, where icons sit in a tight grid.
    static let folderMagnificationShare: CGFloat = 0.5

    /// Folders always magnify at least this much while Magnification is on (the Dock's slider can
    /// be set below the icon size, where the Dock itself stops magnifying).
    static let folderMagnificationFloor: CGFloat = 0.08

    static var dockMagnifies: Bool { (pref("magnification") as? NSNumber)?.boolValue == true }

    /// Starting strength for folder magnification: a proportion of the Dock's own Magnification
    /// slider (until it's set in Settings).
    static var defaultFolderGrowth: CGFloat {
        let tile = tileSize ?? 48
        let large = (pref("largesize") as? NSNumber).map { CGFloat($0.doubleValue) } ?? tile
        let dockGrowth = max(large / tile - 1, 0)
        return min(max(dockGrowth * folderMagnificationShare, folderMagnificationFloor), 0.3)
    }
}

// MARK: - Accessibility view of the Dock

struct DockItem {
    let element: AXUIElement
    let subrole: String
    let title: String
    let url: URL?
    /// Global, top-left-origin coordinates (same space as CGEvent locations).
    let frame: CGRect
}

/// Reads the Dock through the Accessibility API. Safe to call from any thread.
final class DockAX {
    static let shared = DockAX()

    private let lock = NSLock()
    private var pid: pid_t = 0
    private var appElement: AXUIElement?
    private var overviewCheck: (time: TimeInterval, active: Bool)?

    private func dockApp() -> AXUIElement? {
        lock.lock(); defer { lock.unlock() }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            appElement = nil
            return nil
        }
        if running.processIdentifier != pid || appElement == nil {
            pid = running.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            appElement = element
        }
        return appElement
    }

    func reset() {
        lock.lock(); appElement = nil; pid = 0; lock.unlock()
    }

    var list: AXUIElement? {
        guard let app = dockApp() else { return nil }
        let children: [AXUIElement] = AX.value(app, kAXChildrenAttribute) ?? []
        return children.first { (AX.value($0, kAXRoleAttribute) as String?) == kAXListRole }
    }

    var items: [DockItem] {
        guard let list else { return [] }
        let children: [AXUIElement] = AX.value(list, kAXChildrenAttribute) ?? []
        return children.compactMap { Self.item($0) }
    }

    func item(for url: URL) -> DockItem? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        return items.first { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path == target }
    }

    /// The Dock item under a global (top-left origin) point, if any.
    func item(at point: CGPoint) -> DockItem? {
        guard let app = dockApp() else { return nil }
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit)
        if error == .invalidUIElement || error == .cannotComplete { reset() }
        guard error == .success, var element = hit else { return nil }
        for _ in 0..<3 {
            if let item = Self.item(element), item.subrole.hasSuffix("DockItem") { return item }
            guard let parent: AXUIElement = AX.value(element, kAXParentAttribute) else { break }
            element = parent
        }
        return nil
    }

    /// The overview can win the system hit test even over the Dock. In that case, use the
    /// live frames of the Dock's accessible tiles, within the visible Dock list.
    func itemForOpening(at point: CGPoint) -> DockItem? {
        if let item = item(at: point) { return item }
        guard FolderPrefs.opensInOverview, let list, AX.frame(list).contains(point), overviewIsActive else { return nil }
        let children: [AXUIElement] = AX.value(list, kAXChildrenAttribute) ?? []
        return children.compactMap { element -> DockItem? in
            let frame = AX.frame(element)
            guard frame.contains(point), let item = Self.item(element, frame: frame),
                  item.subrole.hasSuffix("DockItem") else { return nil }
            return item
        }.min { a, b in
            hypot(a.frame.midX - point.x, a.frame.midY - point.y)
                < hypot(b.frame.midX - point.x, b.frame.midY - point.y)
        }
    }

    /// Mission Control and App Exposé publish their accessibility groups through WindowManager
    /// on macOS 27 and through the Dock on macOS 26. The Dock can also expose empty groups.
    var overviewIsActive: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = lock.withLock({ overviewCheck }), now - cached.time < 0.1 { return cached.active }

        let active: Bool
        if #available(macOS 27, *), let manager = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.WindowManager"
        ).first {
            let app = AXUIElementCreateApplication(manager.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.1)
            let children: [AXUIElement] = AX.value(app, kAXChildrenAttribute) ?? []
            active = children.contains { child in
                let id: String? = AX.value(child, kAXIdentifierAttribute)
                return id == "mc.display" || id == "appexpose.display"
            }
        } else if let app = dockApp() {
            let children: [AXUIElement] = AX.value(app, kAXChildrenAttribute) ?? []
            active = children.contains { child in
                let id: String? = AX.value(child, kAXIdentifierAttribute)
                guard id == "mc" || id == "appexpose" else { return false }
                let groups: [AXUIElement] = AX.value(child, kAXChildrenAttribute) ?? []
                return !groups.isEmpty
            }
        } else {
            active = false
        }
        lock.withLock {
            if overviewCheck.map({ $0.time < now }) ?? true { overviewCheck = (now, active) }
        }
        return active
    }

    private static func item(_ element: AXUIElement, frame: CGRect? = nil) -> DockItem? {
        guard let subrole: String = AX.value(element, kAXSubroleAttribute) else { return nil }
        let url: URL? = (AX.value(element, kAXURLAttribute) as NSURL?) as URL?
        return DockItem(element: element, subrole: subrole,
                        title: AX.value(element, kAXTitleAttribute) ?? "",
                        url: url, frame: frame ?? AX.frame(element))
    }

    /// Where the Dock bar's inner edge sits when nothing is magnified (global, top-left origin):
    /// the top for a bottom Dock, the right edge for a left Dock, the left edge for a right Dock.
    /// Tiles far from the pointer are never magnified, so the extreme value is the resting one.
    /// While an auto-hiding Dock is still sliding in this is further out; callers keep the innermost value.
    func restingInnerEdge() -> CGFloat? {
        let frames = items.map(\.frame).filter { $0.width > 0 && $0.height > 0 }
        guard !frames.isEmpty else { return nil }
        switch CoreDock.orientation {
        case .bottom: return frames.map(\.minY).max()
        case .left: return frames.map(\.maxX).min()
        case .right: return frames.map(\.minX).max()
        }
    }

    /// Resting distance from one app tile to the next (icon size + the Dock's spacing).
    /// Unmagnified tiles are the smallest, so the minimum is the resting value.
    func restingPitch() -> CGFloat? {
        let tiles = items.filter { $0.subrole == "AXApplicationDockItem" }.map(\.frame)
        let sizes = tiles.map { CoreDock.orientation == .bottom ? $0.width : $0.height }.filter { $0 > 0 }
        return sizes.min()
    }

    // MARK: Holding the Dock open

    /// Puts the Dock into its keyboard-focus state, which keeps an auto-hiding Dock on screen
    /// without changing the usable screen area (so no windows get resized).
    ///
    /// Something has to stay selected for that state to last, and the Dock marks it: a selected
    /// tile is drawn dimmed with its name label showing. Selecting the folder's own tile puts that
    /// label right where the popup covers it. (Selecting the divider instead leaves every icon
    /// bright, but the Dock then re-shows the last label it drew above the divider, on its own.)
    @discardableResult
    func holdOpen(selecting item: DockItem?) -> Bool {
        guard let list else { return false }
        let ok = AXUIElementSetAttributeValue(list, "AXFocused" as CFString, kCFBooleanTrue) == .success
        if let item {
            AXUIElementSetAttributeValue(list, "AXSelectedChildren" as CFString, [item.element] as CFArray)
        }
        return ok
    }

    func releaseHold() {
        guard let list else { return }
        AXUIElementSetAttributeValue(list, "AXFocused" as CFString, kCFBooleanFalse)
    }

    /// Dock menus that macOS draws in the Dock's helper process (DockHelper) rather than the Dock
    /// itself, as it sometimes does. They aren't attached to the tile there, so look for them.
    func helperMenus() -> [AXUIElement] {
        guard let helper = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock.helper").first else { return [] }
        let app = AXUIElementCreateApplication(helper.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows: [AXUIElement] = AX.value(app, kAXWindowsAttribute) ?? []
        return windows.flatMap { window -> [AXUIElement] in
            let children: [AXUIElement] = AX.value(window, kAXChildrenAttribute) ?? []
            return children.filter { (AX.value($0, kAXRoleAttribute) as String?) == kAXMenuRole }
        }
    }

    /// Closes a Dock menu that's open on another tile (opening a folder should dismiss it,
    /// as clicking any other Dock icon would).
    ///
    /// Only through Accessibility: Escape sent to a Dock process that has no menu to cancel makes
    /// the system's "not allowed" sound.
    func dismissMenus() {
        helperMenus().forEach { AXUIElementPerformAction($0, kAXCancelAction as CFString) }
        for item in items {
            guard let menu: AXUIElement = AX.value(item.element, "AXShownMenuUIElement") else { continue }
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
    }

    var isFocused: Bool {
        guard let list else { return false }
        return (AX.value(list, "AXFocused") as Bool?) ?? false
    }

    /// "Show All Windows" for an app that has a tile in the Dock (running apps always do).
    func showExposé(forAppAt url: URL) -> Bool {
        guard let item = item(for: url) else { return false }
        return AXUIElementPerformAction(item.element, "AXShowExpose" as CFString) == .success
    }
}

// MARK: - Small AX helpers

enum AX {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func frame(_ element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let v: AnyObject = value(element, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &origin)
        }
        if let v: AnyObject = value(element, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Dock preferences (adding / removing tiles)

enum DockPrefs {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "persistent-apps" as CFString

    private static func readApps() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
    }

    private static func writeApps(_ apps: [[String: Any]]) {
        CFPreferencesSetAppValue(key, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        let url = string.hasPrefix("file:") ? URL(string: string) : URL(fileURLWithPath: string)
        return url?.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func normalized(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private static func appTile(url: URL, label: String, bundleID: String?) -> [String: Any] {
        var data: [String: Any] = [
            "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            "file-label": label,
            "file-type": 41,
        ]
        if let bundleID { data["bundle-identifier"] = bundleID }
        return ["tile-type": "file-tile", "tile-data": data]
    }

    static func folderTile(_ folder: Folder) -> [String: Any] {
        var tile = appTile(url: folder.stubURL, label: folder.name, bundleID: folder.bundleIdentifier)
        if var data = tile["tile-data"] as? [String: Any] {
            data["dock-extra"] = true
            tile["tile-data"] = data
        }
        return tile
    }

    /// Where the Dock tile with this bundle identifier points (a folder keeps its identifier
    /// across renames, so this finds its tile even when it still uses an older stub).
    static func tileURL(bundleID: String) -> URL? {
        for tile in readApps() {
            guard let data = tile["tile-data"] as? [String: Any],
                  data["bundle-identifier"] as? String == bundleID,
                  let path = path(of: tile) else { continue }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    // Changes made live, through the Dock's menus, that it hasn't saved yet (it writes its
    // settings a few seconds later). Until it does, they count as done.
    // If the Dock hasn't confirmed one after a while, it didn't happen: trust the Dock again.
    private static var livePinned: [String: (tile: [String: Any], since: Date)] = [:]
    private static var liveRemoved: [String: Date] = [:]
    private static let liveTimeout: TimeInterval = 12

    static func noteLivePin(_ url: URL, tile: [String: Any]) {
        let target = normalized(url)
        liveRemoved.removeValue(forKey: target)
        livePinned[target] = (tile, Date())
        noteDockEdited()
    }

    static func noteLiveRemoval(_ url: URL) {
        let target = normalized(url)
        livePinned.removeValue(forKey: target)
        liveRemoved[target] = Date()
        noteDockEdited()
    }

    // The Dock saves its list a few seconds after anything changes in it (a tile dragged,
    // kept or removed). A restart before then would undo that change, or the Dock, quitting
    // with it unsaved, could write its old list over the one just written. So restarts wait.
    private static var lastDockEdit = Date.distantPast
    private static let dockSaveDelay: TimeInterval = 4

    static func noteDockEdited() { lastDockEdit = Date() }

    /// Runs `work` once the Dock has had time to save its latest changes.
    static func whenDockSaved(_ work: @escaping () -> Void) {
        let wait = dockSaveDelay - Date().timeIntervalSince(lastDockEdit)
        if wait <= 0 { work() } else { DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work) }
    }

    /// Calls back once a restarted Dock (a process other than `oldPID`) is up with its tiles.
    static func whenDockRestarted(from oldPID: pid_t?, deadline: Date = Date().addingTimeInterval(6),
                                  then work: @escaping () -> Void) {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        if let pid, pid != oldPID, !DockAX.shared.items.isEmpty {
            // Give it a moment to finish adding running apps.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }
        guard Date() < deadline else { work(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { whenDockRestarted(from: oldPID, deadline: deadline, then: work) }
    }

    /// Takes every tile of a folder out of `tiles`: its stub, an older stub still waiting for a
    /// rename, or any tile with its bundle identifier. Returns where the first one was.
    static func removeFolderTiles(bundleID: String, urls: [URL], from tiles: inout [[String: Any]]) -> Int? {
        let targets = Set(urls.map(normalized))
        func belongs(_ tile: [String: Any]) -> Bool {
            if let p = path(of: tile), targets.contains(p) { return true }
            return ((tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) == bundleID
        }
        let first = tiles.firstIndex(where: belongs)
        tiles.removeAll(where: belongs)
        return first
    }

    /// Drops a live change that didn't happen after all.
    static func forgetLive(_ url: URL) {
        let target = normalized(url)
        livePinned.removeValue(forKey: target)
        liveRemoved.removeValue(forKey: target)
    }

    static func containsTile(for url: URL) -> Bool {
        let target = normalized(url)
        let saved = readApps().contains { path(of: $0) == target }
        if let pin = livePinned[target] {
            if saved || Date().timeIntervalSince(pin.since) > liveTimeout {
                livePinned.removeValue(forKey: target)
                return saved
            }
            return true
        }
        if let since = liveRemoved[target] {
            if !saved || Date().timeIntervalSince(since) > liveTimeout {
                liveRemoved.removeValue(forKey: target)
                return saved
            }
            return false
        }
        return saved
    }

    /// What the Dock has actually saved (ignoring live changes it hasn't written yet).
    static func savedContains(_ url: URL) -> Bool {
        let target = normalized(url)
        return readApps().contains { path(of: $0) == target }
    }

    /// Where a tile sits among the Dock's apps (counting live changes).
    static func index(of url: URL) -> Int? {
        var apps = readApps()
        reconcileLive(&apps)
        return index(of: url, in: apps)
    }

    /// Brings saved settings up to date with live changes the Dock hasn't written yet, so a
    /// restart doesn't undo them.
    private static func reconcileLive(_ apps: inout [[String: Any]]) {
        let now = Date()
        apps.removeAll { tile in
            guard let p = path(of: tile), let since = liveRemoved[p] else { return false }
            return now.timeIntervalSince(since) <= liveTimeout
        }
        for (target, pin) in livePinned where now.timeIntervalSince(pin.since) <= liveTimeout
            && !apps.contains(where: { path(of: $0) == target }) {
            apps.append(pin.tile)
        }
    }

    /// Applies a change to the Dock's app list and restarts the Dock so it takes effect.
    static func modify(restartWhenHidden: Bool = false, then completion: (() -> Void)? = nil,
                       _ change: (inout [[String: Any]]) -> Void) {
        var apps = readApps()
        reconcileLive(&apps)
        livePinned.removeAll()
        liveRemoved.removeAll()
        change(&apps)
        writeApps(apps)
        if restartWhenHidden {
            restartDockWhenHidden(then: completion)
        } else {
            restartDock()
            completion?()
        }
    }

    /// True between writing a change and the Dock restarting to show it.
    private(set) static var restartPending = false

    /// Restarts the Dock once an auto-hiding Dock is out of sight (or after a while regardless).
    static func restartDockWhenHidden(deadline: Date = Date().addingTimeInterval(20), then completion: (() -> Void)? = nil) {
        restartPending = true
        guard CoreDock.autoHideEnabled, Date() < deadline, !isDockHidden else {
            restartDock()
            restartPending = false
            completion?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { restartDockWhenHidden(deadline: deadline, then: completion) }
    }

    private static var isDockHidden: Bool {
        guard let list = DockAX.shared.list else { return true }
        let frame = AX.frame(list)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // Screens in AX (top-left origin) space.
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        switch CoreDock.orientation {
        case .bottom: return !screens.contains { $0.minX <= frame.midX && frame.midX < $0.maxX && frame.minY < $0.maxY - 1 }
        case .left: return !screens.contains { $0.minY <= frame.midY && frame.midY < $0.maxY && frame.maxX > $0.minX + 1 }
        case .right: return !screens.contains { $0.minY <= frame.midY && frame.midY < $0.maxY && frame.minX < $0.maxX - 1 }
        }
    }

    static func index(of url: URL, in apps: [[String: Any]]) -> Int? {
        apps.firstIndex { path(of: $0) == normalized(url) }
    }

    static func appTile(for appURL: URL) -> [String: Any] {
        let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        return appTile(url: appURL, label: name, bundleID: Bundle(url: appURL)?.bundleIdentifier)
    }

    static func restartDock() {
        DockAX.shared.reset()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }
}
