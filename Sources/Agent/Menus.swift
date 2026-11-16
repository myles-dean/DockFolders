import AppKit

// MARK: - Right-click on an app inside a folder (mirrors the Dock's own app menu)

enum AppMenu {
    static func entries(for app: FolderApp, folderID: String) -> [MenuEntry] {
        let panel = FolderPanelController.shared
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL
        }
        // The app's name heads the menu, unless the folder already shows names under its icons.
        var entries: [MenuEntry] = FolderPrefs.showsNames ? [] : [.header(app.name), .separator]

        // Window list, like the Dock.
        if let running {
            let windows = Self.windows(of: running)
            for window in windows {
                entries.append(.action(window.title, indicator: window.minimized ? .diamond : .none) {
                    panel.close()
                    if window.minimized {
                        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                    running.activate()
                })
            }
            if !windows.isEmpty { entries.append(.separator) }
        }

        entries.append(.submenu(L10n.text("Options"), [
            .action(L10n.text("Remove from Folder")) { FolderActions.removeApp(app.url, from: folderID, deleteIfEmpty: true) },
            .action(L10n.text("Move to Dock")) { FolderActions.moveAppToDock(app.url, from: folderID) },
            .separator,
            .action(L10n.text("Show in Finder")) {
                panel.close()
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            },
        ]))
        entries.append(.separator)

        if let running {
            entries.append(.action(L10n.text("Show All Windows")) {
                panel.close()
                if !DockAX.shared.showExposé(forAppAt: app.url) { running.activate() }
            })
            if running.isHidden {
                entries.append(.action(L10n.text("Show")) { running.unhide(); running.activate(); panel.close() })
            } else {
                entries.append(.action(L10n.text("Hide")) { panel.stayOpenThroughAppSwitch(); running.hide() })
            }
            var quit = MenuEntry.action(L10n.text("Quit")) { panel.stayOpenThroughAppSwitch(); running.terminate() }
            quit.alternate = (L10n.text("Force Quit"), { panel.stayOpenThroughAppSwitch(); running.forceTerminate() })
            entries.append(quit)
        } else {
            entries.append(.action(L10n.text("Open")) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
                panel.close()
            })
        }
        return entries
    }

    private struct AppWindow { let element: AXUIElement; let title: String; let minimized: Bool }

    private static func windows(of app: NSRunningApplication) -> [AppWindow] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let windows: [AXUIElement] = AX.value(element, kAXWindowsAttribute) ?? []
        return windows.compactMap { window in
            guard (AX.value(window, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
                  let title: String = AX.value(window, kAXTitleAttribute), !title.isEmpty else { return nil }
            return AppWindow(element: window, title: title, minimized: AX.value(window, kAXMinimizedAttribute) ?? false)
        }
    }
}

// MARK: - Menus shown at Dock tiles

enum DockMenus {
    /// Right-click on a folder tile: everything else lives in Settings.
    static func folderEntries(folderID: String) -> [MenuEntry] {
        guard FolderStore.shared.folder(id: folderID) != nil else { return [] }
        let settings = SettingsController.shared
        return [
            .action(L10n.text("Edit Name…")) { settings.show(folderID: folderID, editingName: true) },
            .action(L10n.text("Add Apps…")) { settings.addApps(to: folderID) },
            .action(L10n.text("Empty Folder")) { FolderActions.emptyFolder(folderID) },
            .separator,
            .action(L10n.text("Settings…")) { settings.show(folderID: folderID) },
        ]
    }

    /// Shows a menu attached to a Dock tile (where its name tag goes), keeping the Dock on screen.
    static func show(_ entries: [MenuEntry], at item: DockItem) {
        guard !entries.isEmpty else { return }
        let panel = FolderPanelController.shared
        if panel.isOpen { panel.close() }

        let held = CoreDock.autoHideEnabled && DockAX.shared.holdOpen(selecting: item)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let tip: CGPoint
        switch CoreDock.orientation {
        case .bottom: tip = CGPoint(x: item.frame.midX, y: primaryHeight - (item.frame.minY + DockLabel.tipInset))
        case .left, .right: tip = CGPoint(x: item.frame.midX, y: primaryHeight - item.frame.minY + 8)
        }
        GlassMenuController.shared.showAttached(
            entries, tip: tip, minWidth: DockLabel.width(for: item.title) + 10, watchingDockFocus: held
        ) {
            if held, !panel.isOpen { DockAX.shared.releaseHold() }
        }
    }
}
