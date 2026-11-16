import AppKit

struct Folder: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Paths of the apps in this folder, in display order.
    var apps: [String]
    /// File name of this folder's stub app inside `DFShared.stubsDirectory`.
    var stubName: String
    /// Set when you turn off Show in Dock, so adding apps doesn't bring the folder back.
    var keepOutOfDock: Bool? = nil
    /// Folders get one of a few reusable stub identifiers ("slots"), so macOS only announces a new
    /// Dock tile extension the first time a slot is ever used, not for every new folder (it keys
    /// them on the identifier, wherever the stub is). Folders made before slots keep their own.
    var slot: Int? = nil

    var appURLs: [URL] { apps.map { URL(fileURLWithPath: $0) } }
    var stubURL: URL { DFShared.stubsDirectory.appendingPathComponent(stubName, isDirectory: true) }
    var bundleIdentifier: String { DFShared.stubBundleIDPrefix + (slot.map { "slot\($0)" } ?? id) }
    /// Names the folder's tile image; stable per slot, as the Dock may keep a slot's plug-in loaded.
    var tileKey: String { slot.map { "slot\($0)" } ?? id }

}

/// Persists folders as JSON in Application Support.
final class FolderStore {
    static let shared = FolderStore()

    private struct FileFormat: Codable { var folders: [Folder] }

    private(set) var folders: [Folder] = []

    /// Called after any change, with the folder that changed (nil when one was removed).
    var onChange: ((Folder?) -> Void)?

    /// Also posted after any change (Settings listens to it).
    static let didChange = Notification.Name("DockFoldersStoreDidChange")

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: DFShared.storeURL),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data) else { return }
        folders = file.folders
    }

    private func save() {
        try? FileManager.default.createDirectory(at: DFShared.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(FileFormat(folders: folders)) {
            try? data.write(to: DFShared.storeURL, options: .atomic)
        }
    }

    func folder(id: String) -> Folder? { folders.first { $0.id == id } }

    func folder(stubURL: URL) -> Folder? {
        let path = stubURL.standardizedFileURL.resolvingSymlinksInPath().path
        return folders.first { $0.stubURL.standardizedFileURL.resolvingSymlinksInPath().path == path }
    }

    @discardableResult
    func create(name: String, apps: [URL]) -> Folder {
        var id = ""
        repeat {
            id = (0..<16).map { _ in String("0123456789abcdef".randomElement()!) }.joined()
        } while folder(id: id) != nil
        let used = Set(folders.compactMap(\.slot))
        let slot = (1...).first { !used.contains($0) }!
        let folder = Folder(id: id, name: name, apps: Self.unique(apps.map(\.path)),
                            stubName: uniqueStubName(for: name, excluding: nil), slot: slot)
        folders.append(folder)
        save()
        onChange?(folder)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return folder
    }

    @discardableResult
    func update(_ id: String, _ mutate: (inout Folder) -> Void) -> Folder? {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&folders[index])
        folders[index].apps = Self.unique(folders[index].apps)
        save()
        onChange?(folders[index])
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return folders[index]
    }

    func delete(_ id: String) {
        folders.removeAll { $0.id == id }
        save()
        onChange?(nil)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// A file-system friendly, unique stub bundle name for a folder name.
    func uniqueStubName(for name: String, excluding id: String?) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base.hasPrefix(".") { base = L10n.text("Folder") + base }
        var candidate = base + ".app"
        var n = 2
        let taken = Set(folders.filter { $0.id != id }.map { $0.stubName.lowercased() })
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n).app"
            n += 1
        }
        return candidate
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
