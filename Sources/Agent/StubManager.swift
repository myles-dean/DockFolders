import AppKit

/// Builds the small per-folder apps that live in the Dock, and keeps their tile images current.
enum StubManager {
    private static let classPlaceholder = "DFTile_ZZZZZZZZZZZZZZZZ"

    static var templateURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("FolderStub.app", isDirectory: true)
    }

    static var isDarkMode: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style?.lowercased() == "dark"
    }

    /// Creates (or rebuilds) the stub app for a folder at `folder.stubURL`.
    static func install(_ folder: Folder) throws {
        let fm = FileManager.default
        stopIndicator(folder)   // a running copy would keep the old code; it restarts on the next app event
        try fm.createDirectory(at: DFShared.stubsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: DFShared.tilesDirectory, withIntermediateDirectories: true)

        let staging = DFShared.stubsDirectory.appendingPathComponent(".\(folder.id)-staging.app", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: templateURL, to: staging)

        let contents = staging.appendingPathComponent("Contents")
        let plugin = contents.appendingPathComponent("PlugIns/FolderTile.docktileplugin")
        // Unique among the plug-ins the Dock loads, and the same for a slot whoever uses it.
        let className = "DFTile_" + (folder.slot.map { String(format: "slot%012d", $0) } ?? folder.id)

        try editPlist(contents.appendingPathComponent("Info.plist")) { info in
            info["CFBundleIdentifier"] = folder.bundleIdentifier
            info["CFBundleName"] = folder.name
            info["CFBundleDisplayName"] = folder.name
            info[DFShared.folderIDInfoKey] = folder.id
            info[DFShared.tileKeyInfoKey] = folder.tileKey
        }
        try editPlist(plugin.appendingPathComponent("Contents/Info.plist")) { info in
            info["CFBundleIdentifier"] = folder.bundleIdentifier + ".tile"
            info["NSPrincipalClass"] = className
            info[DFShared.folderIDInfoKey] = folder.id
            info[DFShared.tileKeyInfoKey] = folder.tileKey
        }

        // Give this copy of the plug-in a unique Objective-C class name (same length as the placeholder).
        let binary = plugin.appendingPathComponent("Contents/MacOS/FolderTile")
        var data = try Data(contentsOf: binary)
        let from = Data(classPlaceholder.utf8), to = Data(className.utf8)
        precondition(from.count == to.count)
        var searchStart = data.startIndex
        while let range = data.range(of: from, in: searchStart..<data.endIndex) {
            data.replaceSubrange(range, with: to)
            searchStart = range.upperBound
        }
        try data.write(to: binary)

        TileRenderer.writeICNS(apps: folder.appURLs, dark: isDarkMode,
                               to: contents.appendingPathComponent("Resources/AppIcon.icns"))

        // Ad-hoc sign the inner plug-in, then the app.
        try codesign(plugin)
        try codesign(staging)

        let destination = folder.stubURL
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
        LSRegisterURL(destination as CFURL, true)
        refreshTile(folder)
        registerWithSystem(destination)
    }

    /// Launches the stub once, invisibly. Until an app has been launched, macOS doesn't trust it
    /// "for binding" and the Dock refuses to load its tile plug-in.
    private static func registerWithSystem(_ stubURL: URL) {
        let path = stubURL.standardizedFileURL.resolvingSymlinksInPath().path
        registering.insert(path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.arguments = ["--register"]
        NSWorkspace.shared.openApplication(at: stubURL, configuration: config) { app, _ in
            DispatchQueue.main.async { waitUntilQuit(app, path: path, deadline: Date().addingTimeInterval(5)) }
        }
    }

    /// Stubs on their one-time registration run (they quit straight away). Launching one again
    /// before it's gone would just hand back that quitting instance.
    static var registering = Set<String>()

    private static func waitUntilQuit(_ app: NSRunningApplication?, path: String, deadline: Date) {
        guard let app, !app.isTerminated, Date() < deadline else { registering.remove(path); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitUntilQuit(app, path: path, deadline: deadline) }
    }

    static func remove(_ folder: Folder) {
        stopIndicator(folder)
        LSRegisterURL(folder.stubURL as CFURL, false)
        try? FileManager.default.removeItem(at: folder.stubURL)
        try? FileManager.default.removeItem(at: DFShared.tileImageURL(for: folder.tileKey))
    }

    /// Re-renders the folder's tile image and tells its Dock plug-in to redraw.
    static func refreshTile(_ folder: Folder) {
        try? FileManager.default.createDirectory(at: DFShared.tilesDirectory, withIntermediateDirectories: true)
        if let png = TileRenderer.pngData(apps: folder.appURLs, pixelSize: 512, dark: isDarkMode) {
            try? png.write(to: DFShared.tileImageURL(for: folder.tileKey), options: .atomic)
        }
        DistributedNotificationCenter.default().postNotificationName(
            DFShared.tileChangedNotification, object: folder.tileKey, userInfo: nil, deliverImmediately: true)
    }

    /// Whether any app in the folder is running.
    static func hasRunningApp(_ folder: Folder, running: Set<String> = FolderPanelController.runningAppPaths()) -> Bool {
        folder.appURLs.contains { running.contains($0.standardizedFileURL.path) }
    }

    /// The Dock only draws its running dot for running apps, so while any app in the folder is
    /// running, the folder's own stub runs too (--indicator) and the Dock shows the real dot.
    /// Folders whose stub is running to change the Dock (pinning or unpinning its tile).
    static var busy = Set<String>()

    static func syncIndicator(_ folder: Folder, running: Bool) {
        guard !busy.contains(folder.id) else { return }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: folder.bundleIdentifier)
        // Only for folders that are in the Dock: otherwise the stub would show up as a loose app.
        if running, instances.isEmpty, FileManager.default.fileExists(atPath: folder.stubURL.path),
           DockPrefs.containsTile(for: folder.stubURL) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            config.arguments = ["--indicator"]
            NSWorkspace.shared.openApplication(at: folder.stubURL, configuration: config) { _, _ in }
        } else if !running || !DockPrefs.containsTile(for: folder.stubURL) {
            instances.forEach { $0.terminate() }
        }
    }

    static func stopIndicator(_ folder: Folder) {
        NSRunningApplication.runningApplications(withBundleIdentifier: folder.bundleIdentifier).forEach { $0.terminate() }
    }

    /// Quits the folder's stub and calls back once it's gone (forcing it near the end of `wait`).
    /// A stub still running when the Dock restarts comes back as a running tile.
    static func quit(_ folder: Folder, wait: TimeInterval = 2, then done: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(wait)
        func check() {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: folder.bundleIdentifier)
                .filter { !$0.isTerminated }
            guard !running.isEmpty, Date() < deadline else { done(); return }
            let force = deadline.timeIntervalSinceNow < 0.7
            running.forEach { _ = force ? $0.forceTerminate() : $0.terminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
        }
        check()
    }

    // MARK: - Helpers

    private static func editPlist(_ url: URL, _ edit: (inout [String: Any]) -> Void) throws {
        let data = try Data(contentsOf: url)
        guard var dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        edit(&dict)
        let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try out.write(to: url)
    }

    private static func codesign(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--timestamp=none", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "DockFolders", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: L10n.format("codesign failed for %@", url.lastPathComponent)])
        }
    }
}
