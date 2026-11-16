import AppKit

/// Settings → General → "Open folders on hover": a folder opens when the pointer rests on its
/// Dock tile for a moment, as if it had been clicked. Once per visit: after it's closed, the
/// pointer has to leave the tile and come back to open it again.
final class FolderHover {
    static let shared = FolderHover()

    private var monitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    /// The folder under the pointer, since when, and whether this visit has opened it already.
    private var hovered: (id: String, since: Date, opened: Bool)?

    func update() {
        if FolderPrefs.opensOnHover { start() } else { stop() }
    }

    /// A folder was opened by a click: this visit to its tile counts as having opened it.
    func noteOpened(_ folderID: String) {
        if hovered?.id == folderID { hovered?.opened = true }
    }

    private func start() {
        guard monitor == nil else { return }
        // Only plain moves: watching costs nothing until the pointer nears the Dock.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.moved() }
        // Moves go to the active app, which is this one while Settings is in front.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.moved()
            return event
        }
    }

    private func stop() {
        for m in [monitor, localMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(m) }
        monitor = nil
        localMonitor = nil
        timer?.invalidate()
        timer = nil
        hovered = nil
    }

    private func moved() {
        guard timer == nil, nearDock(NSEvent.mouseLocation) else { return }
        // Near the Dock: check what's under the pointer a few times a second until it leaves.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.check() }
        check()
    }

    private func check() {
        let mouse = NSEvent.mouseLocation
        guard nearDock(mouse) else {
            timer?.invalidate()
            timer = nil
            hovered = nil
            return
        }
        let panel = FolderPanelController.shared
        // Not while a button is down (a click or a drag) or a menu is open.
        guard NSEvent.pressedMouseButtons == 0, !GlassMenuController.shared.isOpen,
              let item = DockAX.shared.item(at: CGPoint(x: mouse.x, y: primaryHeight - mouse.y)),
              let folderID = FolderStore.shared.folders.first(where: {
                  FolderActions.dockURL(for: $0).standardizedFileURL.resolvingSymlinksInPath().path
                      == item.url?.standardizedFileURL.resolvingSymlinksInPath().path
              })?.id
        else {
            // On the popup (or anywhere else): the visit to the tile is over.
            if !panel.popupContains(mouse) { hovered = nil }
            return
        }
        if hovered?.id != folderID {
            hovered = (folderID, Date(), panel.folderID == folderID)
        }
        guard let current = hovered, !current.opened,
              Date().timeIntervalSince(current.since) >= FolderPrefs.hoverDelay else { return }
        hovered?.opened = true
        guard panel.folderID != folderID else { return }
        panel.show(folderID: folderID, item: item, pointerInitiated: true)
        panel.openedByHover = true
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Within reach of the Dock's edge of the screen the pointer is on (Cocoa coordinates).
    private func nearDock(_ p: CGPoint) -> Bool {
        let band: CGFloat = 160
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        let s = screen.frame
        switch CoreDock.orientation {
        case .bottom: return p.y < s.minY + band
        case .left: return p.x < s.minX + band
        case .right: return p.x > s.maxX - band
        }
    }
}
