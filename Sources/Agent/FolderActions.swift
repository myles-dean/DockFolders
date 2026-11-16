import AppKit
import UniformTypeIdentifiers

/// Everything that creates, edits or removes folders (and the matching Dock tiles).
enum FolderActions {
    private static var store: FolderStore { .shared }

    // MARK: Creating

    /// New folders are named after their apps' categories (see FolderNaming), or "Folder" when
    /// the apps don't say; you can rename them in Settings.
    static var folderName: String { L10n.text("Folder") }

    /// An app dragged onto another app in the Dock: the two become a folder, named after their
    /// categories, in their place. Both apps' tiles leave the Dock together, then the folder
    /// comes in where they were.
    static func combineInDock(dragged: URL, onto target: URL) {
        let apps = [target, dragged]
        let folder = store.create(name: FolderNaming.name(for: apps), apps: apps)
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            stubFailed(L10n.text("Couldn’t create the folder."), error)
            return
        }
        takeFromOtherFolders(apps, except: folder.id)
        EventInterceptor.shared.update(folders: store.folders)
        FolderPanelController.shared.close()
        // Never by restarting the Dock: if something can't be done live, it's left as it is.
        takeOutOfDockTogether([dragged, target]) {
            DockPrefs.noteLivePin(folder.stubURL, tile: DockPrefs.folderTile(folder))
            DockLive.placeFolderAtPointer(folder) { _ in
                // Make sure it really is in the Dock now; if not, put it in (at the end).
                DockLive.verifyKept(folder, url: folder.stubURL) { kept in
                    if !kept { showInDock(folder) }
                    EventInterceptor.shared.update(folders: store.folders)
                    NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
                }
            }
        }
    }

    /// Takes apps' tiles out of the Dock together, retrying a few times while the Dock finishes a
    /// drop. Apps that aren't open go first: they just poof. Open ones only stop being kept, which
    /// makes the Dock move them along and rebuild its tiles, so they come after. Never restarts it.
    private static func takeOutOfDockTogether(_ urls: [URL], completion: @escaping () -> Void) {
        urls.forEach(DockPrefs.noteLiveRemoval)
        let open = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        var remaining = urls.sorted { !open.contains($0.standardizedFileURL.path) && open.contains($1.standardizedFileURL.path) }
        func pass(_ attemptsLeft: Int) {
            var first = true
            remaining = remaining.filter { url in
                guard DockAX.shared.item(for: url) != nil else { return false }   // already gone
                // A moment between them for the Dock to finish with the last menu.
                if !first { usleep(200_000) }
                first = false
                return !DockLive.unpinApp(at: url)
            }
            guard !remaining.isEmpty, attemptsLeft > 1 else {
                remaining.forEach(DockPrefs.forgetLive)   // still there: say so
                // A beat for the poofs before anything else moves.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { completion() }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pass(attemptsLeft - 1) }
        }
        // A moment for the Dock to finish setting a dropped tile down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pass(5) }
    }

    /// Creates a folder and adds its tile to the end of the Dock's apps.
    static func createFolder(apps: [URL]) {
        let apps = apps.filter { $0.pathExtension == "app" }
        let folder = store.create(name: FolderNaming.name(for: apps), apps: apps)
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            stubFailed(L10n.text("Couldn’t create the folder."), error)
            return
        }
        takeFromOtherFolders(apps, except: folder.id)
        EventInterceptor.shared.update(folders: store.folders)
        if !folder.apps.isEmpty { showInDock(folder) }
    }

    /// Re-adds folders whose tiles were dragged out of the Dock (their contents were kept).
    static func putBackInDock(_ folderIDs: [String]) {
        // Only folders with something in them belong in the Dock.
        let folders = folderIDs.compactMap(store.folder(id:))
            .filter { !$0.apps.isEmpty && !DockPrefs.containsTile(for: dockURL(for: $0)) }
        func next(_ rest: ArraySlice<Folder>) {
            guard let folder = rest.first else { return }
            showInDock(folder) { _ in next(rest.dropFirst()) }
        }
        next(folders[...])
    }

    // MARK: The Dock, live

    /// Puts a folder's tile in the Dock with no restart and no sound (see DockLive), checking the
    /// Dock really kept it and trying once more if not. Never restarts the Dock: if it still won't,
    /// the folder stays out of it (Settings shows Show in Dock off).
    private static func showInDock(_ folder: Folder, attempts: Int = 2, completion: @escaping (Bool) -> Void = { _ in }) {
        if !FileManager.default.fileExists(atPath: folder.stubURL.path) { try? StubManager.install(folder) }
        DockPrefs.noteLivePin(folder.stubURL, tile: DockPrefs.folderTile(folder))
        NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
        DockLive.pinFolder(folder) { kept in
            if !kept, attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showInDock(folder, attempts: attempts - 1, completion: completion) }
                return
            }
            if !kept { DockPrefs.forgetLive(folder.stubURL) }
            StubManager.syncIndicator(folder, running: StubManager.hasRunningApp(folder))
            EventInterceptor.shared.update(folders: store.folders)
            NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
            completion(kept)
        }
    }

    /// Takes a folder's tile out of the Dock with no restart and no poof (see DockLive).
    private static func hideFromDock(_ folder: Folder, completion: @escaping () -> Void = {}) {
        let tileURL = dockURL(for: folder)
        // The tile is going, so a name still waiting to reach it doesn't matter any more.
        let oldStub = pendingRenames.removeValue(forKey: folder.id)
        FolderPanelController.shared.close(ifShowing: folder.id)
        DockPrefs.noteLiveRemoval(tileURL)
        DockSettle.forget(folder.id)
        NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
        DockLive.unpinFolder(folder, tileURL: tileURL) { ok in
            if !ok { DockPrefs.whenDockSaved { DockPrefs.modify { _ in } } }
            if let oldStub, oldStub.path != folder.stubURL.path { removeStub(at: oldStub) }
            EventInterceptor.shared.update(folders: store.folders)
            NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
            completion()
        }
    }

    /// An app dragged from the Dock onto a folder: it goes into the folder, and its tile leaves the
    /// Dock as quickly as possible.
    static func dropFromDock(_ url: URL, into folderID: String, releasedOnDock: Bool) {
        DockPrefs.noteLiveRemoval(url)
        add([url], to: folderID, removeFromDock: false)
        if releasedOnDock {
            // Let go on the Dock itself: the Dock has just set the tile down beside the folder. Take
            // it out the moment its menu answers (a running app just stops being kept).
            removeWhenSettled(url, attempts: 5)
        } else {
            // Let go above the Dock: the Dock removes the tile itself, as for any app dragged off.
            // If it was let go too close and the Dock kept it, take it out.
            let running = NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path
            }
            guard !running else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if DockAX.shared.item(for: url) != nil { DockLive.unpinApp(at: url) }
            }
        }
    }

    private static func removeWhenSettled(_ url: URL, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if DockLive.unpinApp(at: url) || attempts <= 1 { return }
            removeWhenSettled(url, attempts: attempts - 1)
        }
    }

    /// Puts all of a folder's apps back in the Dock where the folder was, and deletes the folder.
    /// Apps that aren't open can only get a Dock tile when the Dock restarts, so this does one
    /// restart right away (taking anything else waiting for one along with it). Apps already
    /// kept in the Dock stay where they are.
    static func emptyFolder(_ folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        FolderPanelController.shared.close(ifShowing: folderID)
        let tileURL = dockURL(for: folder)
        let apps = folder.appURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        StubManager.busy.insert(folder.id)
        let oldStub = pendingRenames.removeValue(forKey: folderID)
        var stubURLs = [folder.stubURL]
        for url in [tileURL, oldStub].compactMap({ $0 }) where !stubURLs.contains(url) { stubURLs.append(url) }
        store.delete(folderID)   // gone from Settings at once
        DockSettle.forget(folderID)
        EventInterceptor.shared.update(folders: store.folders)
        // Its stub (running while an app inside is open) must be gone first: one still running
        // when the Dock restarts comes back as a running tile, a "?" once its file is deleted.
        StubManager.quit(folder) {
            putAppsBack(from: folder, apps: apps, stubURLs: stubURLs, retry: true)
        }
    }

    /// One restart that swaps the folder's tile for its apps; then checks it took (the Dock can
    /// write its old list back as it quits) and tidies anything left before deleting the stub.
    private static func putAppsBack(from folder: Folder, apps: [URL], stubURLs: [URL], retry: Bool) {
        var dockPID: pid_t?
        DockSettle.apply(including: { tiles in
            dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            let index = DockPrefs.removeFolderTiles(bundleID: folder.bundleIdentifier, urls: stubURLs, from: &tiles)
            let appTiles = apps.filter { DockPrefs.index(of: $0, in: tiles) == nil }.map(DockPrefs.appTile(for:))
            tiles.insert(contentsOf: appTiles, at: min(index ?? tiles.count, tiles.count))
        }, then: {
            DockPrefs.whenDockRestarted(from: dockPID) {
                let appsMissing = apps.contains { !DockPrefs.savedContains($0) }
                let folderLeft = stubURLs.contains(where: DockPrefs.savedContains)
                if retry, appsMissing || folderLeft {
                    putAppsBack(from: folder, apps: apps, stubURLs: stubURLs, retry: false)
                    return
                }
                // Still showing a tile for the folder? Take it out before its stub goes.
                for url in stubURLs where DockAX.shared.item(for: url) != nil { _ = DockLive.unpinApp(at: url) }
                for url in stubURLs where url.path != folder.stubURL.path { removeStub(at: url) }
                StubManager.remove(folder)
                StubManager.busy.remove(folder.id)
            }
        })
    }

    /// A folder dragged onto another: all its apps move in (after the others), and the dragged
    /// folder, left empty, goes (its tile leaving the Dock).
    static func mergeFolder(_ sourceID: String, into targetID: String) {
        guard sourceID != targetID, let source = store.folder(id: sourceID), store.folder(id: targetID) != nil else { return }
        // An app lives in one folder, so adding them here takes them out of the source, which is
        // deleted once empty.
        add(source.appURLs, to: targetID, removeFromDock: false)
        if store.folder(id: sourceID) != nil { delete(sourceID) }   // e.g. its apps no longer exist
    }

    /// Takes apps' tiles out of the Dock (each with the Dock's poof, unless the app is running:
    /// then it just stops being kept). Never restarts the Dock.
    private static func takeOutOfDock(_ urls: [URL], completion: @escaping () -> Void = {}) {
        guard !urls.isEmpty else { completion(); return }
        takeOutOfDockTogether(urls, completion: completion)
    }

    // MARK: Adding / removing apps

    /// An app lives in one folder at a time: putting it in a folder moves it there, out of any
    /// other. A folder left empty by that goes, as when you take out its last app yourself.
    private static func takeFromOtherFolders(_ urls: [URL], except folderID: String?) {
        let paths = Set(urls.map(\.path))
        for other in store.folders where other.id != folderID && other.apps.contains(where: paths.contains) {
            guard let updated = store.update(other.id, { $0.apps.removeAll(where: paths.contains) }) else { continue }
            StubManager.refreshTile(updated)
            if updated.apps.isEmpty { delete(other.id) }
        }
    }

    static func add(_ appURLs: [URL], to folderID: String, removeFromDock: Bool) {
        let apps = appURLs.filter { $0.pathExtension == "app" }
        guard !apps.isEmpty, let before = store.folder(id: folderID),
              let folder = store.update(folderID, { $0.apps += apps.map(\.path) }) else { return }
        takeFromOtherFolders(apps, except: folderID)
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()

        // A folder joins the Dock once it has its first app (unless you turned Show in Dock off).
        let joinDock = before.apps.isEmpty && !folder.apps.isEmpty && folder.keepOutOfDock != true
            && !DockPrefs.containsTile(for: dockURL(for: folder))
        let leavingDock = removeFromDock ? apps.filter(DockPrefs.containsTile(for:)) : []
        guard joinDock || !leavingDock.isEmpty else { return }
        FolderPanelController.shared.close()
        takeOutOfDock(leavingDock) {
            if joinDock { showInDock(folder) }
        }
    }

    static func chooseApps(for folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = L10n.format("Add Apps to “%@”", folder.name)
        panel.prompt = L10n.text("Add")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        // Its own identity, so it remembers the view you last used in it (e.g. Gallery) apart from
        // other open panels. (macOS doesn't let apps pick the view themselves.)
        panel.identifier = NSUserInterfaceItemIdentifier("DockFoldersAddApps")
        if let window = SettingsController.shared.settingsWindow, window.isVisible {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { add(panel.urls, to: folderID, removeFromDock: false) }
            }
            return
        }
        let response = panel.runModal()
        previous?.activate()
        if response == .OK { add(panel.urls, to: folderID, removeFromDock: false) }
    }

    /// `deleteIfEmpty`: from the folder itself, taking out its last app deletes the folder (like
    /// iOS). From Settings it's kept, empty and out of the Dock, until apps are added again.
    static func removeApp(_ url: URL, from folderID: String, deleteIfEmpty: Bool = false) {
        guard let folder = store.update(folderID, { $0.apps.removeAll { $0 == url.path } }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()
        guard folder.apps.isEmpty else { return }
        if deleteIfEmpty { delete(folderID) } else { removeFromDock(folderID) }
    }

    static func moveAppToDock(_ url: URL, from folderID: String) {
        guard let folder = store.update(folderID, { $0.apps.removeAll { $0 == url.path } }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.close()
        if !DockPrefs.containsTile(for: url) {
            let running = NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path
            }
            if running {
                // Its tile is already showing; just keep it (silent).
                DockPrefs.noteLivePin(url, tile: DockPrefs.appTile(for: url))
                let pin = { if !DockLive.pinRunningApp(at: url) { DockPrefs.whenDockSaved { DockPrefs.modify { _ in } } } }
                // With open apps kept in their folders, the Dock only now gives it its tile back.
                if OpenAppsInFolders.isActive { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: pin) } else { pin() }
            } else {
                // Only a restart can add a tile for an app that isn't open: save it for a quiet moment.
                DockSettle.addApp(url, near: folderID)
            }
        }
        // Its last app: the folder goes (like iOS).
        if folder.apps.isEmpty { delete(folderID) }
    }

    /// Empty folders have nothing to show, so they're kept out of the Dock.
    static func removeEmptyFoldersFromDock() {
        let empty = store.folders.filter { $0.apps.isEmpty && DockPrefs.containsTile(for: dockURL(for: $0)) }
        func next(_ rest: ArraySlice<Folder>) {
            guard let folder = rest.first else { return }
            hideFromDock(folder) { next(rest.dropFirst()) }
        }
        next(empty[...])
    }

    // MARK: Folder-level

    // MARK: Renaming (from Settings)

    /// Renames waiting to reach the Dock: folder id → the stub its Dock tile still points at.
    /// The Dock only reads names when it starts, so they go out with the next unseen restart
    /// (see DockSettle), or straight away with Update Now.
    private static var pendingRenames: [String: URL] = [:]

    static func hasPendingRename(_ folderID: String) -> Bool { pendingRenames[folderID] != nil }
    static var hasPendingRenames: Bool { !pendingRenames.isEmpty }

    /// Hands the waiting renames to DockSettle, which writes them into the Dock.
    static func takePendingRenames() -> [String: URL] {
        defer { pendingRenames.removeAll() }
        return pendingRenames
    }

    /// After a rename reached the Dock: the old stubs can go.
    static func finishRenames(_ renames: [String: URL]) {
        let currentStubs = Set(store.folders.map { $0.stubURL.path })
        for old in renames.values where !currentStubs.contains(old.path) { removeStub(at: old) }
    }

    /// The stub the folder's Dock tile currently points at.
    /// Making a folder's app failed: usually because App Management is off, which the setup
    /// window explains (and lets you turn on); anything else, say so.
    static func stubFailed(_ title: String, _ error: Error) {
        if !Permissions.checkAppManagement() {
            OnboardingController.shared.show()
        } else {
            Prompt.error(title, error)
        }
    }

    static func dockURL(for folder: Folder) -> URL { pendingRenames[folder.id] ?? folder.stubURL }

    static func rename(_ folderID: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = store.folder(id: folderID), name != folder.name else { return }
        let tileURL = dockURL(for: folder)
        let inDock = DockPrefs.containsTile(for: tileURL)
        let previousStub = folder.stubURL
        let stubName = store.uniqueStubName(for: name, excluding: folderID)
        // Record which stub the Dock tile still uses *before* the store announces the change,
        // so anything refreshing right then (Settings) still sees the folder as in the Dock.
        let newStubPath = DFShared.stubsDirectory.appendingPathComponent(stubName, isDirectory: true).path
        if inDock, tileURL.path != newStubPath {
            pendingRenames[folderID] = tileURL
        } else {
            pendingRenames.removeValue(forKey: folderID)   // back to the name the Dock already shows
        }
        guard let renamed = store.update(folderID, { $0.name = name; $0.stubName = stubName }) else { return }
        do {
            try StubManager.install(renamed)
        } catch {
            stubFailed(L10n.text("Couldn’t rename the folder."), error)
            return
        }
        // A stub from an earlier rename that never reached the Dock can go right away.
        if previousStub.path != tileURL.path, previousStub.path != renamed.stubURL.path {
            removeStub(at: previousStub)
        }
        if !inDock, tileURL.path != renamed.stubURL.path {
            removeStub(at: tileURL)
        }
        EventInterceptor.shared.update(folders: store.folders)
        FolderPanelController.shared.close()
        NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
        DockSettle.changed()
    }

    /// Picks up renames that hadn't reached the Dock when Dock Folders last quit: the tile still
    /// points at the folder's old stub. They go out with the next unseen restart.
    static func recoverPendingRenames() {
        for folder in store.folders where pendingRenames[folder.id] == nil {
            guard !DockPrefs.containsTile(for: folder.stubURL),
                  let tileURL = DockPrefs.tileURL(bundleID: folder.bundleIdentifier),
                  tileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
                    == DFShared.stubsDirectory.resolvingSymlinksInPath().path else { continue }
            pendingRenames[folder.id] = tileURL
        }
        guard !pendingRenames.isEmpty else { return }
        EventInterceptor.shared.update(folders: store.folders)
        DockSettle.changed()
    }

    private static func removeStub(at url: URL) {
        LSRegisterURL(url as CFURL, false)
        try? FileManager.default.removeItem(at: url)
    }

    /// Takes a folder's tile out of the Dock but keeps the folder (it can be put back from Settings).
    static func removeFromDock(_ folderID: String) {
        guard let folder = store.folder(id: folderID), DockPrefs.containsTile(for: dockURL(for: folder)) else { return }
        hideFromDock(folder)
    }

    /// Deletes a folder entirely (its apps stay installed). It's gone from Settings at once; its
    /// tile slides out of the Dock a moment later.
    static func delete(_ folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        FolderPanelController.shared.close(ifShowing: folderID)
        let inDock = DockPrefs.containsTile(for: dockURL(for: folder))
        store.delete(folderID)
        EventInterceptor.shared.update(folders: store.folders)
        if inDock {
            hideFromDock(folder) { StubManager.remove(folder) }
        } else {
            if let old = pendingRenames.removeValue(forKey: folderID), old.path != folder.stubURL.path { removeStub(at: old) }
            DockSettle.forget(folderID)
            StubManager.remove(folder)
        }
    }

    /// Sets a folder's app order (from Settings); the Dock icon's 2×2 preview follows.
    static func setAppOrder(_ folderID: String, _ urls: [URL]) {
        guard let folder = store.folder(id: folderID) else { return }
        let ordered = urls.map(\.path)
        let rest = folder.apps.filter { !ordered.contains($0) }
        guard ordered + rest != folder.apps,
              let updated = store.update(folderID, { $0.apps = ordered + rest }) else { return }
        StubManager.refreshTile(updated)
        FolderPanelController.shared.reload()
    }

    /// Reorders a folder's apps (from Settings); the Dock icon's 2×2 preview follows.
    static func moveApps(in folderID: String, from offsets: IndexSet, to destination: Int) {
        guard let folder = store.update(folderID, { folder in
            var apps = folder.apps
            let moving = offsets.map { apps[$0] }
            for index in offsets.sorted(by: >) { apps.remove(at: index) }
            let insertAt = destination - offsets.filter { $0 < destination }.count
            apps.insert(contentsOf: moving, at: max(0, min(insertAt, apps.count)))
            folder.apps = apps
        }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()
    }

    /// An empty new folder. It joins the Dock (at the end of its apps) once it has an app.
    @discardableResult
    static func newEmptyFolder() -> String? {
        let folder = store.create(name: folderName, apps: [])
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            stubFailed(L10n.text("Couldn’t create the folder."), error)
            return nil
        }
        EventInterceptor.shared.update(folders: store.folders)
        return folder.id
    }

    // MARK: Helpers

}

// MARK: - Small modal prompts

enum Prompt {
    static func text(title: String, message: String?, defaultValue: String, confirm: String, icon: NSImage?) -> String? {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        if let icon { alert.icon = icon }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: L10n.text("Cancel"))
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        previous?.activate()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirm: String, icon: NSImage?) -> Bool {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let icon { alert.icon = icon }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: L10n.text("Cancel"))
        let response = alert.runModal()
        previous?.activate()
        return response == .alertFirstButtonReturn
    }

    static func error(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("OK"))
        NSApp.activate()
        alert.runModal()
    }
}
