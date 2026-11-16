import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FolderStore.shared
    private var trustTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private let welcomedKey = "DFWelcomed"
    private var languageObservers: [NSObjectProtocol] = []
    private var setupCompleted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy only.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: DFShared.agentBundleID)
            .contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }

        try? FileManager.default.createDirectory(at: DFShared.stubsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: DFShared.tilesDirectory, withIntermediateDirectories: true)

        handleTerminationSignals()
        installMainMenu()
        languageObservers.append(NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            FolderPanelController.shared.close(animated: false)
            GlassMenuController.shared.closeAll()
            DockTag.shared.hide()
            self?.installMainMenu()
        })
        languageObservers.append(NotificationCenter.default.addObserver(forName: Localization.didConfirm, object: nil, queue: .main) { [weak self] _ in
            self?.startAfterLanguageSelection()
        })
        startAfterLanguageSelection()
    }

    private func startAfterLanguageSelection() {
        guard Localization.shared.hasChosen else {
            OnboardingController.shared.show()
            return
        }
        guard !setupCompleted else { return }
        setupCompleted = true
        wireInterceptor()
        reconcileStubs()
        observeSystem()
        DockSettle.startObserving()
        // After any Dock restart from reconciling has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refreshRunningDots() }
        registerLoginItem()
        startWhenTrusted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FolderPanelController.shared.close(animated: false)
        // Nobody would keep the folders' running dots up to date.
        store.folders.forEach(StubManager.stopIndicator)
    }

    /// Opening the app again (Finder, Spotlight) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Localization.shared.hasChosen { SettingsController.shared.show() }
        else { OnboardingController.shared.show() }
        return false
    }

    // MARK: dockfolders:// URLs (sent by folder stubs)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == DFShared.urlScheme {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            // dockfolders://create?path=/Applications/A.app&path=… (handy for scripting)
            #if DFTEST
            // Test builds only (DF_SWIFT_FLAGS="-D DFTEST"): runs Create Folder on two Dock apps.
            if url.host == "test-preview", let id = items.first(where: { $0.name == "id" })?.value {
                FolderPanelController.shared.show(folderID: id, item: nil)
                FolderPanelController.shared.previewDrop(of: items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) })
                continue
            }
            if url.host == "test-remove", let id = items.first(where: { $0.name == "id" })?.value {
                for path in items.filter({ $0.name == "path" }).compactMap(\.value) {
                    FolderActions.removeApp(URL(fileURLWithPath: path), from: id)
                }
                continue
            }
            if url.host == "test-close" { FolderPanelController.shared.close(); OnboardingController.shared.dismiss(); continue }
            if url.host == "test-onboarding" { OnboardingController.shared.show(); continue }
            if url.host == "test-show", let id = items.first(where: { $0.name == "id" })?.value {
                FolderPanelController.shared.show(folderID: id, item: nil)
                continue
            }
            if url.host == "test-unpin" {
                for path in items.filter({ $0.name == "path" }).compactMap(\.value) {
                    DockPrefs.noteLiveRemoval(URL(fileURLWithPath: path))
                    _ = DockLive.unpinApp(at: URL(fileURLWithPath: path))
                }
                continue
            }
            if url.host == "test-empty", let id = items.first(where: { $0.name == "id" })?.value {
                FolderActions.emptyFolder(id)
                continue
            }
            if url.host == "test-merge", let from = items.first(where: { $0.name == "from" })?.value,
               let to = items.first(where: { $0.name == "to" })?.value {
                FolderActions.mergeFolder(from, into: to)
                FolderPanelController.shared.showDropLanded()
                continue
            }
            if url.host == "test-combine" {
                let paths = items.filter { $0.name == "path" }.compactMap(\.value)
                if paths.count == 2 {
                    FolderActions.combineInDock(dragged: URL(fileURLWithPath: paths[0]), onto: URL(fileURLWithPath: paths[1]))
                }
                continue
            }
            #endif
            if url.host == "create" {
                let paths = items.filter { $0.name == "path" }.compactMap(\.value)
                FolderActions.createFolder(apps: paths.map { URL(fileURLWithPath: $0) })
                continue
            }
            guard let id = items.first(where: { $0.name == "id" })?.value, store.folder(id: id) != nil else { continue }
            switch url.host {
            case "open":
                if FolderPanelController.shared.folderID != id {
                    // Picked in ⌘-Tab: the folder hands focus straight back to your app, which
                    // shouldn't close the folder it just opened.
                    if items.contains(where: { $0.name == "source" && $0.value == "switcher" }) {
                        FolderPanelController.shared.stayOpenThroughAppSwitch()
                    }
                    FolderPanelController.shared.show(folderID: id, item: nil)
                }
            case "restore":
                FolderActions.putBackInDock([id])
            case "settings":
                // dockfolders://settings?id=…&editName=1 opens it with the name ready to type;
                // …&addApps=1 with the Add Apps window open.
                if items.contains(where: { $0.name == "addApps" && $0.value == "1" }) {
                    SettingsController.shared.addApps(to: id)
                } else {
                    let editName = items.contains { $0.name == "editName" && $0.value == "1" }
                    SettingsController.shared.show(folderID: id, editingName: editName)
                }
            case "add":
                let paths = items.filter { $0.name == "path" }.compactMap(\.value)
                FolderActions.add(paths.map { URL(fileURLWithPath: $0) }, to: id, removeFromDock: false)
            default:
                break
            }
        }
    }

    // MARK: Setup

    /// Quit cleanly on SIGTERM/SIGINT (e.g. `kill`, logout) so the Dock is never left held open.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                FolderPanelController.shared.close(animated: false)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func wireInterceptor() {
        let interceptor = EventInterceptor.shared
        interceptor.update(folders: store.folders)
        interceptor.onFolderClick = { id, item in FolderPanelController.shared.toggle(folderID: id, item: item) }
        interceptor.onFolderMenu = { id, item in DockMenus.show(DockMenus.folderEntries(folderID: id), at: item) }
        interceptor.onOutsideClick = { FolderPanelController.shared.close() }
        interceptor.onAppDragBegan = { DockDragCollector.shared.began($0) }
        interceptor.onAppDragMoved = { DockDragCollector.shared.moved(to: $0) }
        interceptor.onAppDragEnded = { DockDragCollector.shared.ended(at: $0) }
        interceptor.onMenuOutsideClick = { GlassMenuController.shared.closeAll() }

        store.onChange = { [weak self] _ in
            EventInterceptor.shared.update(folders: FolderStore.shared.folders)
            self?.refreshRunningDots()
            OpenAppsInFolders.syncList()
        }
    }

    /// Makes sure every folder has an up-to-date stub app and tile image.
    private func reconcileStubs() {
        let templateHash = Bundle(url: StubManager.templateURL)?.object(forInfoDictionaryKey: "DFTemplateHash") as? String
        var rebuilt = false
        for folder in store.folders {
            let stubHash = Bundle(url: folder.stubURL).flatMap {
                NSDictionary(contentsOf: $0.bundleURL.appendingPathComponent("Contents/Info.plist"))?["DFTemplateHash"] as? String
            }
            if stubHash == nil || stubHash != templateHash {
                try? StubManager.install(folder)
                rebuilt = rebuilt || stubHash != nil
            } else {
                StubManager.refreshTile(folder)
            }
        }
        // The Dock keeps old plug-in code loaded until it restarts: do that at a quiet moment.
        if rebuilt { DockSettle.restartLater() }
        FolderActions.removeEmptyFoldersFromDock()
        FolderActions.recoverPendingRenames()
    }

    private func observeSystem() {
        // Light/Dark changes: re-render tiles.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                FolderStore.shared.folders.forEach(StubManager.refreshTile)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            EventInterceptor.shared.updateScreens()
            FolderPanelController.shared.close(animated: false)
        }
        // Folder tiles get the Dock's running dot while any app inside is running.
        RunningApps.shared.start()
        FolderHover.shared.update()
        OpenAppsInFolders.start()
        NotificationCenter.default.addObserver(forName: RunningApps.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshRunningDots()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" {
                DockAX.shared.reset()
                // Plug-ins reload with the Dock; nudge them once it's up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    FolderStore.shared.folders.forEach(StubManager.refreshTile)
                    self?.refreshRunningDots()
                }
            }
        }
    }

    /// Keeps each folder's running indicator in step with the apps inside it.
    private func refreshRunningDots() {
        // Mid-rename the Dock still points at the old stub; wait for its restart.
        guard !DockPrefs.restartPending else { return }
        let running = FolderPanelController.runningAppPaths()
        for folder in store.folders {
            StubManager.syncIndicator(folder, running: StubManager.hasRunningApp(folder, running: running))
        }
    }

    private func registerLoginItem() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        let service = SMAppService.mainApp
        if service.status != .enabled { try? service.register() }
    }

    private func startWhenTrusted() {
        guard Localization.shared.hasChosen else {
            OnboardingController.shared.show()
            return
        }
        // A permission missing (always, on a fresh install): walk through turning them on.
        if !Permissions.accessibility || !Permissions.checkAppManagement() {
            OnboardingController.shared.show()
        }
        if Permissions.accessibility {
            start()
            return
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.start()
        }
    }

    private func start() {
        EventInterceptor.shared.start()
        if !UserDefaults.standard.bool(forKey: welcomedKey) {
            UserDefaults.standard.set(true, forKey: welcomedKey)
            // The setup window opens Settings itself when you're done with it.
            if !OnboardingController.shared.isShowing { SettingsController.shared.show() }
        }
    }

    // MARK: Menu bar (only seen while Settings is open)

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("Close Settings"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        // No ⌘Q: quitting stops folders working, so it's a deliberate choice in Settings.
        appMenu.addItem(withTitle: L10n.text("Quit Dock Folders"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.text("Edit"))
        edit.addItem(withTitle: L10n.text("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L10n.text("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.text("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.text("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.text("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.text("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
