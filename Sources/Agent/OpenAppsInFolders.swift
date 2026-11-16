import AppKit
import Darwin

/// Settings → General → "Open apps only in their folders".
///
/// macOS gives every open app its own Dock tile, and only the Dock can leave one out. With System
/// Integrity Protection partly off, a small root helper loads code into the Dock that leaves out
/// the tiles of apps in folders (Sources/DockHook). With SIP on, none of that can run, and this
/// stays off.
///
/// The Dock side reads ~/Library/Application Support/Dock Folders/HiddenInDock.plist (which apps)
/// and reports back by writing HookStatus.plist and posting HookLoaded.
enum OpenAppsInFolders {
    static let didChange = Notification.Name("DockFoldersOpenAppsDidChange")

    private static let label = "com.mylesdean.DockFolders.helper"
    private static let helperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(label)")
    private static let payloadURL = URL(fileURLWithPath: "/Library/Application Support/Dock Folders/DockFoldersHook.dylib")
    private static let daemonURL = URL(fileURLWithPath: "/Library/LaunchDaemons/\(label).plist")
    private static var bundledDir: URL { Bundle.main.resourceURL!.appendingPathComponent("DockHook") }

    private static var listURL: URL { DFShared.supportDirectory.appendingPathComponent("HiddenInDock.plist") }
    private static var statusURL: URL { DFShared.supportDirectory.appendingPathComponent("HookStatus.plist") }
    private static var pausedURL: URL { DFShared.supportDirectory.appendingPathComponent("HookPaused") }

    // MARK: What this Mac allows

    struct Readiness {
        var appleSilicon: Bool
        var filesystemOff: Bool     // SIP: Filesystem Protections disabled
        var debuggingOff: Bool      // SIP: Debugging Restrictions disabled (task_for_pid)
        var bootArgSet: Bool        // -arm64e_preview_abi (Apple silicon only)
        var ready: Bool { filesystemOff && debuggingOff && (!appleSilicon || bootArgSet) }
    }

    static var readiness: Readiness {
        // Same checks as yabai's scripting addition (csr_get_active_config, kern.bootargs).
        typealias CSRFn = @convention(c) (UnsafeMutablePointer<UInt32>) -> Int32
        var config: UInt32 = 0
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csr_get_active_config") {
            _ = unsafeBitCast(sym, to: CSRFn.self)(&config)
        }
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let appleSilicon = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1
        var bootArgs = [CChar](repeating: 0, count: 2048)
        var length = bootArgs.count - 1
        let args = sysctlbyname("kern.bootargs", &bootArgs, &length, nil, 0) == 0 ? String(cString: bootArgs) : ""
        return Readiness(appleSilicon: appleSilicon,
                         filesystemOff: config & 0x02 != 0,      // CSR_ALLOW_UNRESTRICTED_FS
                         debuggingOff: config & 0x04 != 0,       // CSR_ALLOW_TASK_FOR_PID
                         bootArgSet: args.contains("-arm64e_preview_abi"))
    }

    // MARK: State

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "openAppsOnlyInFolders") }
        set { UserDefaults.standard.set(newValue, forKey: "openAppsOnlyInFolders") }
    }

    static var helperInstalled: Bool {
        [helperURL, payloadURL, daemonURL].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The installed helper and payload match this version of Dock Folders.
    static var helperCurrent: Bool {
        func same(_ a: URL, _ b: URL) -> Bool { (try? Data(contentsOf: a)) == (try? Data(contentsOf: b)) && FileManager.default.fileExists(atPath: a.path) }
        return same(helperURL, bundledDir.appendingPathComponent("DockFoldersHelper"))
            && same(payloadURL, bundledDir.appendingPathComponent("DockFoldersHook.dylib"))
    }

    /// Why the helper stopped by itself (the Dock kept quitting after it loaded), if it did.
    static var pausedReason: String? {
        try? String(contentsOf: pausedURL, encoding: .utf8)
    }

    /// Whether the code is running in the Dock right now (and found what it needs there).
    static var isActive: Bool {
        guard enabled, let status = NSDictionary(contentsOf: statusURL),
              let pid = status["pid"] as? Int, status["hooked"] as? Bool == true,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        return Int(dock.processIdentifier) == pid
    }

    /// Loaded into the Dock, but the Dock didn't have what it expected (a newer macOS).
    static var loadedButUnhooked: Bool {
        guard let status = NSDictionary(contentsOf: statusURL), let pid = status["pid"] as? Int,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        return Int(dock.processIdentifier) == pid && status["hooked"] as? Bool == false
    }

    static func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.mylesdean.DockFolders.HookLoaded"), object: nil, queue: .main
        ) { _ in changed() }
        syncList()
    }

    private static func changed() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Turning it on and off

    /// On: installs (or updates) the helper if needed, asking for an administrator password, then
    /// tells the Dock which apps live in folders. Off: the Dock restarts without the helper's code,
    /// so open apps get their own tiles back.
    static func setEnabled(_ on: Bool) {
        if on {
            guard readiness.ready else { return }
            if !helperInstalled || !helperCurrent {
                guard runAsAdmin("install.sh", prompt: L10n.text("Dock Folders needs to install a helper that keeps open apps in their folders.")) else {
                    changed()
                    return
                }
            }
            try? FileManager.default.removeItem(at: pausedURL)
            enabled = true
            syncList()
        } else {
            let wasActive = isActive || loadedButUnhooked
            enabled = false
            syncList()
            if wasActive { restartDock() }
        }
        changed()
    }

    /// Removes the helper (asking for an administrator password) and restarts the Dock without it.
    static func uninstallHelper() {
        guard helperInstalled else { return }
        let wasLoaded = isActive || loadedButUnhooked
        guard runAsAdmin("uninstall.sh", prompt: L10n.text("Dock Folders will remove its Dock helper.")) else { return }
        enabled = false
        syncList()
        if wasLoaded { restartDock() }
        changed()
    }

    private static func restartDock() {
        DockPrefs.whenDockSaved { DockPrefs.restartDock() }
    }

    // MARK: Which apps

    /// Tells the Dock which apps live in folders (only once the option has been used).
    static func syncList() {
        guard enabled || FileManager.default.fileExists(atPath: listURL.path) else { return }
        let apps = FolderStore.shared.folders.flatMap(\.appURLs)
        let list: [String: Any] = [
            "enabled": enabled,
            "paths": apps.map { $0.standardizedFileURL.resolvingSymlinksInPath().path },
            "bundleIDs": apps.compactMap { Bundle(url: $0)?.bundleIdentifier },
        ]
        try? FileManager.default.createDirectory(at: DFShared.supportDirectory, withIntermediateDirectories: true)
        (list as NSDictionary).write(to: listURL, atomically: true)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.mylesdean.DockFolders.HiddenAppsChanged"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    // MARK: Helpers

    /// Runs one of the bundled scripts as root, after macOS asks for an administrator password.
    private static func runAsAdmin(_ script: String, prompt: String) -> Bool {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let path = bundledDir.appendingPathComponent(script).path
        let source = "do shell script \"/bin/sh \" & quoted form of \(quoted(path)) & \" \" & quoted form of \(quoted(bundledDir.path))"
            + " with prompt \(quoted(prompt)) with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {   // -128: cancelled
            Prompt.error(L10n.text("Couldn’t set up the Dock helper."), NSError(domain: "DockFolders", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? L10n.text("Unknown error")]))
        }
        return error == nil
    }
}
