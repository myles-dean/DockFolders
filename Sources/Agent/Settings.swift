import AppKit
import ServiceManagement
import SwiftUI

// Dock Folders' only window: manage folders, in a System Settings–style sidebar layout.
// Opened from a folder's right-click menu, or by opening the app again (Spotlight, Finder).

enum SettingsPage: Hashable {
    case folder(String)
    case general
}

final class SettingsModel: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var inDock: Set<String> = []
    @Published var openAtLogin = false
    @Published var accessibilityAllowed = false
    @Published var appManagementAllowed = false
    @Published var selection: SettingsPage?
    @Published var confirmingDelete: Folder?
    /// A folder whose name field should take focus (all selected, ready to type) when shown.
    @Published var editNameOf: String?

    // Folder appearance (Settings → General).
    @Published var showsNames = FolderPrefs.showsNames { didSet { FolderPrefs.showsNames = showsNames } }
    @Published var appsPerPage = FolderPrefs.appsPerPage { didSet { FolderPrefs.appsPerPage = appsPerPage } }
    @Published var iconSize = Double(FolderPrefs.iconSize) {
        didSet { if abs(iconSize - Double(FolderPrefs.iconSize)) > 0.01 { FolderPrefs.customIconSize = CGFloat(iconSize) } }
    }
    @Published var magnifies = FolderPrefs.magnifies { didSet { FolderPrefs.magnifies = magnifies } }
    @Published var opensOnHover = FolderPrefs.opensOnHover { didSet { FolderPrefs.opensOnHover = opensOnHover } }
    @Published private(set) var hoverDelay = FolderPrefs.hoverDelay
    @Published private(set) var closeDelay = FolderPrefs.closeDelay

    func setHoverDelay(_ value: Double) {
        hoverDelay = FolderPrefs.clampedHoverDelay(value)
        FolderPrefs.hoverDelay = hoverDelay
    }

    func setCloseDelay(_ value: Double) {
        closeDelay = FolderPrefs.clampedHoverDelay(value)
        FolderPrefs.closeDelay = closeDelay
    }

    @Published var magnification = Double(FolderPrefs.magnification) {
        didSet { FolderPrefs.magnification = CGFloat(magnification) }
    }

    var usesDockIconSize: Bool { FolderPrefs.customIconSize == nil }

    func matchDockIconSize() {
        FolderPrefs.customIconSize = nil
        iconSize = Double(FolderPrefs.dockIconSize)
        objectWillChange.send()
    }

    /// Folders whose new name hasn't reached the Dock yet, and whether anything else is waiting
    /// for the Dock's next (unseen) restart.
    @Published var renamesWaiting: Set<String> = []
    @Published var dockChangesWaiting = false

    private var observers: [NSObjectProtocol] = []

    init(observingChanges: Bool = true) {
        guard observingChanges else { return }
        reload()
        for name in [FolderStore.didChange, DockSettle.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
    }

    func reload() {
        folders = FolderStore.shared.folders
        inDock = Set(folders.filter { DockPrefs.containsTile(for: FolderActions.dockURL(for: $0)) }.map(\.id))
        renamesWaiting = Set(folders.filter { FolderActions.hasPendingRename($0.id) }.map(\.id))
        dockChangesWaiting = DockSettle.hasPending
        openAtLogin = SMAppService.mainApp.status == .enabled
        if usesDockIconSize { iconSize = Double(FolderPrefs.dockIconSize) }
        // Options can change outside this window (e.g. `defaults write`); show what's saved.
        if appsPerPage != FolderPrefs.appsPerPage { appsPerPage = FolderPrefs.appsPerPage }
        if showsNames != FolderPrefs.showsNames { showsNames = FolderPrefs.showsNames }
        if magnifies != FolderPrefs.magnifies { magnifies = FolderPrefs.magnifies }
        accessibilityAllowed = AXIsProcessTrusted()
        appManagementAllowed = Permissions.appManagement
        if case .folder(let id) = selection, folder(id) == nil { selection = folders.first.map { .folder($0.id) } ?? .general }
        if selection == nil { selection = folders.first.map { .folder($0.id) } ?? .general }
    }

    func folder(_ id: String) -> Folder? { folders.first { $0.id == id } }

    var selectedFolder: Folder? {
        if case .folder(let id) = selection { return folder(id) }
        return nil
    }

    func tileImage(_ folder: Folder, size: Int = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        if let rep = TileRenderer.render(apps: folder.appURLs, pixelSize: size, dark: StubManager.isDarkMode) {
            image.addRepresentation(rep)
        }
        return image
    }

    func setInDock(_ id: String, _ on: Bool) {
        // Remembered, so a hidden folder doesn't come back on its own when apps are added.
        FolderStore.shared.update(id) { $0.keepOutOfDock = on ? nil : true }
        if on { FolderActions.putBackInDock([id]) } else { FolderActions.removeFromDock(id) }
        reload()
    }

    func setOpenAtLogin(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        reload()
    }

    func addFolder() {
        if let id = FolderActions.newEmptyFolder() {
            reload()
            selection = .folder(id)
        }
    }

    func deleteSelected() {
        confirmingDelete = selectedFolder
    }

    func confirmDelete(_ folder: Folder) {
        let index = folders.firstIndex { $0.id == folder.id } ?? 0
        FolderActions.delete(folder.id)
        reload()
        let remaining = folders
        selection = remaining.isEmpty ? .general : .folder(remaining[min(index, remaining.count - 1)].id)
    }
}

// MARK: - Layout

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            // Drawn by hand (not a List) so rows keep a normal height with real space between them.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Folders"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.bottom, 3)
                    ForEach(model.folders) { folder in
                        SidebarRow(model: model, folder: folder)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            // Starts just under the window buttons rather than below a full toolbar's height.
            .safeAreaPadding(.top, 38)
            .ignoresSafeArea(.container, edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { AddRemoveBar(model: model) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.selection {
                case .folder(let id):
                    FolderDetailView(model: model, folderID: id).id(id)
                case .general, .none:
                    GeneralView(model: model)
                }
            }
            .frame(minWidth: 380)
            // The toolbar strip is empty, so pages start up beside the window buttons.
            .ignoresSafeArea(.container, edges: .top)
        }
        // The sidebar runs the full height under the window buttons; no title in the toolbar.
        .toolbar(removing: .title)
        .frame(minWidth: 640, idealWidth: 700, minHeight: 440, idealHeight: 520)
        .alert(
            L10n.format("Delete “%@”?", model.confirmingDelete?.name ?? L10n.text("Folder")),
            isPresented: Binding(get: { model.confirmingDelete != nil }, set: { if !$0 { model.confirmingDelete = nil } }),
            presenting: model.confirmingDelete
        ) { folder in
            Button(L10n.text("Delete"), role: .destructive) { model.confirmDelete(folder) }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: { _ in
            Text(L10n.text("The apps inside stay installed. Only the folder is removed from your Dock."))
        }
    }
}

/// One folder in the sidebar: icon and name, with a rounded highlight when selected.
private struct SidebarRow: View {
    @ObservedObject var model: SettingsModel
    let folder: Folder

    private var selected: Bool { model.selection == .folder(folder.id) }

    var body: some View {
        Button { model.selection = .folder(folder.id) } label: {
            HStack(spacing: 8) {
                Image(nsImage: model.tileImage(folder, size: 64))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(folder.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The + / − buttons under the sidebar list (like other macOS settings lists), and General.
private struct AddRemoveBar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button { model.addFolder() } label: {
                    Image(systemName: "plus").frame(width: 26, height: 22)
                }
                .help(L10n.text("New Folder"))
                Divider().frame(height: 14)
                Button { model.deleteSelected() } label: {
                    Image(systemName: "minus").frame(width: 26, height: 22)
                }
                .help(L10n.text("Delete Folder"))
                .disabled(model.selectedFolder == nil)
                Spacer()
                Button { model.selection = .general } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(model.selection == .general ? Color.accentColor : Color.secondary)
                        .frame(width: 26, height: 22)
                }
                .help(L10n.text("General"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }
}

// MARK: - Folder page

private struct FolderDetailView: View {
    @ObservedObject var model: SettingsModel
    let folderID: String
    @State private var name = ""
    @State private var savedNote: String?
    @FocusState private var editingName: Bool
    /// The apps in their on-screen order.
    @State private var order: [URL] = []

    init(model: SettingsModel, folderID: String) {
        self.model = model
        self.folderID = folderID
        // Filled in up front (not on appear), so the page never shows an empty name or list.
        let folder = model.folder(folderID)
        _name = State(initialValue: folder?.name ?? "")
        _order = State(initialValue: folder?.appURLs ?? [])
    }

    var body: some View {
        if let folder = model.folder(folderID) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(nsImage: model.tileImage(folder))
                            .resizable()
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            // Not selected when the page opens: click it to edit.
                            TextField(L10n.text("Name"), text: $name, prompt: Text(L10n.text("Folder")))
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .font(.title3.weight(.semibold))
                                .focused($editingName)
                                .onSubmit { save() }
                            if let savedNote {
                                Label(savedNote, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            } else if model.renamesWaiting.contains(folderID) {
                                // The Dock only picks up names when it restarts; that happens unseen.
                                HStack(spacing: 6) {
                                    Text(L10n.text("The Dock shows this name after your Mac next locks or sleeps."))
                                    Button(L10n.text("Update Now")) { DockSettle.apply() }
                                        .buttonStyle(.link)
                                        .help(L10n.text("Restarts the Dock now (the screen flickers for a moment)"))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.text("Shown when you point at it in the Dock"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if isEdited(folder) {
                            Button(L10n.text("Save")) { save() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .keyboardShortcut(.defaultAction)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: isEdited(folder))
                    .animation(.snappy(duration: 0.2), value: savedNote)
                    Toggle(isOn: Binding(
                        get: { model.inDock.contains(folderID) },
                        set: { model.setInDock(folderID, $0) }
                    )) {
                        Text(L10n.text("Show in Dock"))
                        if folder.apps.isEmpty {
                            Text(L10n.text("Add an app first. Empty folders stay out of the Dock."))
                        }
                    }
                    .disabled(folder.apps.isEmpty)
                    .accessibilityLabel(L10n.text("Show in Dock"))
                }

                Section {
                    if order.isEmpty {
                        Text(L10n.text("No apps yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ReorderableApps(order: $order) { FolderActions.setAppOrder(folderID, $0) } remove: {
                            FolderActions.removeApp($0, from: folderID)
                        }
                    }
                } header: {
                    HStack {
                        Text(L10n.text("Apps"))
                        Spacer()
                        Button { FolderActions.chooseApps(for: folderID) } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("Add Apps"))
                    }
                } footer: {
                    Text(L10n.text("Drag to reorder. The first four show on the folder’s icon."))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .onAppear {
                DispatchQueue.main.async { takeNameRequest() }
            }
            .onChange(of: folder.apps) { _, apps in order = apps.map { URL(fileURLWithPath: $0) } }
            .onChange(of: editingName) { _, editing in if !editing { save() } }
            .onChange(of: model.editNameOf) { _, id in if id == folderID { takeNameRequest() } }
            .onDisappear { save() }
        }
    }

    /// "Edit Name…": focus the name with all of it selected, ready to type over.
    /// Otherwise nothing starts out being edited.
    private func takeNameRequest() {
        guard model.editNameOf == folderID else { editingName = false; return }
        model.editNameOf = nil
        editingName = true
        DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
    }

    private func trimmed() -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func isEdited(_ folder: Folder) -> Bool { !trimmed().isEmpty && trimmed() != folder.name }

    private func save() {
        guard let folder = model.folder(folderID), isEdited(folder) else { return }
        FolderActions.rename(folderID, to: name)
        editingName = false
        savedNote = L10n.text("Saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { savedNote = nil }
    }
}

/// The folder's apps as a list you can drag to reorder: the row lifts and follows the pointer,
/// the others slide aside, and it settles into its new place when you let go.
private struct ReorderableApps: View {
    @Binding var order: [URL]
    let save: ([URL]) -> Void
    let remove: (URL) -> Void

    @State private var dragging: URL?
    @State private var startIndex = 0
    @State private var targetIndex = 0
    @State private var dragOffset: CGFloat = 0
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element.path) { index, url in
                let lifted = dragging == url
                AppRow(url: url) { remove(url) }
                    .frame(height: rowHeight)
                    .overlay(alignment: .top) {
                        if index > 0, dragging == nil { Divider().padding(.leading, 36) }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.background.secondary)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                            .padding(.horizontal, -8)
                            .opacity(lifted ? 1 : 0)
                    }
                    .scaleEffect(lifted ? 1.02 : 1)
                    .offset(y: offset(index: index, url: url))
                    .zIndex(lifted ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(drag(url: url, index: index))
            }
        }
        // Measured against the list (not the moving row), so the lifted row tracks the pointer exactly.
        .coordinateSpace(name: "reorder")
    }

    private func offset(index: Int, url: URL) -> CGFloat {
        guard let dragging else { return 0 }
        if url == dragging { return dragOffset }
        if startIndex < targetIndex, index > startIndex, index <= targetIndex { return -rowHeight }
        if startIndex > targetIndex, index >= targetIndex, index < startIndex { return rowHeight }
        return 0
    }

    private func drag(url: URL, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("reorder"))
            .onChanged { value in
                if dragging == nil {
                    withAnimation(.snappy(duration: 0.18)) { dragging = url }
                    startIndex = index
                    targetIndex = index
                }
                dragOffset = value.translation.height
                let target = min(max(startIndex + Int((dragOffset / rowHeight).rounded()), 0), order.count - 1)
                if target != targetIndex {
                    withAnimation(.snappy(duration: 0.22)) { targetIndex = target }
                }
            }
            .onEnded { _ in
                let from = startIndex, to = targetIndex
                // Settle into the new spot, then commit the order.
                withAnimation(.snappy(duration: 0.2)) { dragOffset = CGFloat(to - from) * rowHeight }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    var reordered = order
                    reordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        order = reordered
                        dragging = nil
                        dragOffset = 0
                    }
                    if from != to { save(reordered) }
                }
            }
    }
}

private struct AppRow: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 26, height: 26)
            Text(FolderPanelController.displayName(of: url))
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.text("Remove from Folder"))
        }
    }
}

// MARK: - General page

private struct GeneralView: View {
    @ObservedObject var model: SettingsModel

    private var hoverDelay: Binding<Double> {
        Binding(get: { model.hoverDelay }, set: { model.setHoverDelay($0) })
    }

    var body: some View {
        Form {
            Section {
                LanguagePicker()
            }
            if model.dockChangesWaiting {
                Section {
                    LabeledContent {
                        Button(L10n.text("Update Now")) { DockSettle.apply() }
                    } label: {
                        Text(L10n.text("Dock changes waiting"))
                        Text(L10n.text("New names (and apps put back in the Dock while closed) reach the Dock when your Mac next locks or sleeps, so you never see it restart. Update Now restarts it right away."))
                    }
                }
            }
            Section {
                Toggle(L10n.text("Open at login"), isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                Toggle(isOn: $model.opensOnHover) {
                    Text(L10n.text("Open folders on hover"))
                    Text(L10n.text("A folder opens when the pointer rests on it in the Dock, without a click."))
                }
                DelaySettingRow(title: L10n.text("Open delay"),
                                explanation: L10n.text("Wait 0–2 seconds before opening on hover. Set to 0 for no delay."),
                                value: hoverDelay)
                    .disabled(!model.opensOnHover)
                DelaySettingRow(title: L10n.text("Close delay"),
                                explanation: L10n.text("Wait 0–2 seconds after the pointer leaves. Set to 0 for no delay."),
                                value: Binding(get: { model.closeDelay }, set: { model.setCloseDelay($0) }))
                LabeledContent(L10n.text("Accessibility")) {
                    if model.accessibilityAllowed {
                        Label(L10n.text("Allowed"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(L10n.text("Open Privacy Settings…")) { Permissions.requestAccessibility() }
                    }
                }
                LabeledContent(L10n.text("App Management")) {
                    if model.appManagementAllowed {
                        Label(L10n.text("Allowed"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(L10n.text("Open Privacy Settings…")) { Permissions.requestAppManagement() }
                    }
                }
            }

            Section {
                Picker(L10n.text("Apps per page"), selection: $model.appsPerPage) {
                    ForEach(FolderPrefs.pageSizes, id: \.self) { size in
                        let grid = FolderMetrics.grid(forPageSize: size)
                        Text("\(size)  (\(grid.columns) × \(grid.rows))").tag(size)
                    }
                }
                Picker(L10n.text("Under each app"), selection: $model.showsNames) {
                    Text(L10n.text("Running Indicator")).tag(false)
                    Text(L10n.text("Name")).tag(true)
                }
                Slider(value: $model.iconSize,
                       in: Double(FolderPrefs.iconSizeRange.lowerBound)...Double(max(FolderPrefs.iconSizeRange.upperBound, FolderPrefs.dockIconSize))) {
                    Text(L10n.text("Icon size"))
                } minimumValueLabel: {
                    Text(L10n.text("Small"))
                } maximumValueLabel: {
                    Text(L10n.text("Large"))
                }
                Toggle(L10n.text("Magnification"), isOn: $model.magnifies)
                if model.magnifies {
                    Slider(value: $model.magnification,
                           in: Double(FolderPrefs.magnificationRange.lowerBound)...Double(FolderPrefs.magnificationRange.upperBound)) {
                        Text(L10n.text("Strength"))
                    } minimumValueLabel: {
                        Text(L10n.text("Subtle"))
                    } maximumValueLabel: {
                        Text(L10n.text("Strong"))
                    }
                }
            } header: {
                Text(L10n.text("Inside Folders"))
            } footer: {
                HStack {
                    Text(model.usesDockIconSize ? L10n.text("Icons are the same size as the Dock’s.") : L10n.text("Icons are a different size from the Dock’s."))
                    if !model.usesDockIconSize {
                        Button(L10n.text("Match Dock")) { model.matchDockIconSize() }
                            .buttonStyle(.link)
                    }
                }
                .foregroundStyle(.secondary)
            }

            OpenAppsSection()

            Section(L10n.text("Tips")) {
                Tip(symbol: "cursorarrow.click.2", text: L10n.text("Click a folder in the Dock to open it; drag icons inside to rearrange them."))
                Tip(symbol: "square.and.arrow.down", text: L10n.text("Drag an app from the Dock onto a folder and hold it there: the folder opens; let go to put the app in. Apps from Finder can go straight onto the folder."))
                Tip(symbol: "dock.arrow.down.rectangle", text: L10n.text("Drag an app out of an open folder and onto the Dock to put it back in the Dock."))
                Tip(symbol: "folder.badge.plus", text: L10n.text("Drag an app onto another app in the Dock and hold it there until Create Folder appears; let go to make a folder of the two, named after what they are."))
            }

            Section {
                Button(L10n.text("Quit Dock Folders"), role: .destructive) { NSApp.terminate(nil) }
            } footer: {
                Text(L10n.text("Dock Folders runs in the background and starts at login."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window

final class SettingsController: NSObject, NSWindowDelegate {
    static let shared = SettingsController()

    private let model = SettingsModel()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    /// Opens Settings, optionally on one folder, and brings it to the front.
    var settingsWindow: NSWindow? { window }

    /// Opens Settings on a folder (from its Dock menu) with the Add Apps window open on it.
    func addApps(to folderID: String) {
        show(folderID: folderID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { FolderActions.chooseApps(for: folderID) }
    }

    func show(folderID: String? = nil, editingName: Bool = false) {
        FolderPanelController.shared.close()
        Permissions.checkAppManagement()
        model.reload()
        if let folderID, model.folder(folderID) != nil {
            model.selection = .folder(folderID)
            if editingName { model.editNameOf = folderID }
        }

        if window == nil {
            let model = self.model
            let host = NSHostingController(rootView: LocalizedRoot { SettingsView(model: model) })
            let window = NSWindow(contentViewController: host)
            window.title = "Dock Folders"   // for the Window menu; not shown
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            // An (empty) toolbar is what lets the sidebar run the full height, under the window buttons.
            window.toolbar = NSToolbar(identifier: "DockFoldersSettings")
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 700, height: 520))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("DockFoldersSettings2")
            self.window = window
        }
        // We're a background app, so ask firmly to come forward.
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        // Nothing starts out being edited (unless the name was asked for).
        if !editingName { DispatchQueue.main.async { self.window?.makeFirstResponder(nil) } }
    }

    func close() { window?.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)   // saves a name still being edited
    }
}
