import AppKit
import SwiftUI

/// The two permissions Dock Folders needs, and how to tell whether it has them.
enum Permissions {
    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let appManagementPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!

    /// Accessibility: seeing the Dock's icons and catching clicks on folders.
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        // Adds Dock Folders to the list (switched off) and shows macOS's own prompt.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(accessibilityPane)
    }

    /// App Management: each folder in the Dock is a small app Dock Folders makes and updates, and
    /// macOS only lets apps change other apps with this permission. There's no way to ask
    /// whether it's on, so this does what making a folder does — rewrite the Info.plist of a copy
    /// of the folder app — and sees whether macOS allows it. (When it doesn't, macOS lists Dock
    /// Folders under App Management, switched off, and may show a notice.)
    @discardableResult
    static func checkAppManagement() -> Bool {
        let fm = FileManager.default
        let probe = DFShared.supportDirectory.appendingPathComponent(".permission-check.app", isDirectory: true)
        let info = probe.appendingPathComponent("Contents/Info.plist")
        if !fm.fileExists(atPath: info.path) {
            try? fm.createDirectory(at: DFShared.supportDirectory, withIntermediateDirectories: true)
            try? fm.removeItem(at: probe)
            guard (try? fm.copyItem(at: StubManager.templateURL, to: probe)) != nil else { return false }
        }
        guard let data = try? Data(contentsOf: info) else { return false }
        appManagement = (try? data.write(to: info)) != nil
        return appManagement
    }

    /// The last result of `checkAppManagement()`.
    private(set) static var appManagement = false

    static func requestAppManagement() {
        checkAppManagement()
        NSWorkspace.shared.open(appManagementPane)
    }

    static var allGranted: Bool { accessibility && appManagement }
}

/// First launch (or any launch missing a permission): a small window that walks through turning
/// on Accessibility and App Management, ticking each off as it's done.
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var window: NSWindow?
    private let model = OnboardingModel()
    private var languageObserver: NSObjectProtocol?

    override init() {
        super.init()
        languageObserver = NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L10n.text("Welcome to Dock Folders")
            self?.resizeToContent()
        }
    }

    func resizeToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, let view = window.contentView else { return }
            view.layoutSubtreeIfNeeded()
            window.setContentSize(view.fittingSize)
        }
    }

    var isShowing: Bool { window?.isVisible == true }

    func show() {
        model.choosingLanguage = !Localization.shared.hasChosen
        if !model.choosingLanguage { model.refresh(checkAppManagement: true) }
        if window == nil {
            let model = self.model
            let host = NSHostingController(rootView: LocalizedRoot { [weak self] in
                OnboardingView(model: model) { self?.finish() }
            })
            let window = NSWindow(contentViewController: host)
            window.title = L10n.text("Welcome to Dock Folders")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            // Size to the content before centring (it starts out tiny).
            window.setContentSize(host.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        model.startWatching()
    }

    func dismiss() { window?.close() }

    private func finish() {
        window?.close()
        SettingsController.shared.show()
    }

    // Back from System Settings: see whether App Management was turned on.
    func windowDidBecomeKey(_ notification: Notification) {
        if !model.choosingLanguage { model.refresh(checkAppManagement: true) }
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
    }
}

final class OnboardingModel: ObservableObject {
    @Published var choosingLanguage = !Localization.shared.hasChosen
    @Published var accessibility = Permissions.accessibility
    @Published var appManagement = Permissions.appManagement
    /// Shown once App Management was asked for but still reads as off (a relaunch can help).
    @Published var askedForAppManagement = false
    private var timer: Timer?

    func refresh(checkAppManagement: Bool) {
        accessibility = Permissions.accessibility
        appManagement = checkAppManagement ? Permissions.checkAppManagement() : Permissions.appManagement
    }

    /// Accessibility can be checked for free, so it's watched; App Management is checked when the
    /// window comes back to the front (checking it when off makes macOS show a notice).
    func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Permissions.accessibility
            if now != self.accessibility { self.accessibility = now }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let done: () -> Void

    var body: some View {
        Group {
            if model.choosingLanguage { languageSelection } else { permissions }
        }
        .onChange(of: model.choosingLanguage) { _, _ in OnboardingController.shared.resizeToContent() }
    }

    private var languageSelection: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text(L10n.text("Choose Your Language")).font(.title2.weight(.semibold))
            Text(L10n.text("Choose the language for Dock Folders. You can change it later in Settings."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            LanguagePicker().pickerStyle(.menu)
            Button(L10n.text("Continue")) {
                // Set the step before notifying startup, which may bring this window forward.
                model.choosingLanguage = false
                Localization.shared.confirm()
                model.refresh(checkAppManagement: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 460)
    }

    private var permissions: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, 28)
            Text(L10n.text("Welcome to Dock Folders"))
                .font(.title2.weight(.semibold))
                .padding(.top, 10)
            Text(L10n.text("Folders for your Dock need two permissions. Turn each one on in System Settings, then come back here."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 32)

            LanguagePicker()
                .padding(.top, 12)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                PermissionRow(symbol: "accessibility", title: L10n.text("Accessibility"),
                              detail: L10n.text("Lets Dock Folders see the Dock and open a folder when you click it."),
                              granted: model.accessibility) {
                    Permissions.requestAccessibility()
                }
                PermissionRow(symbol: "app.badge.checkmark", title: L10n.text("App Management"),
                              detail: L10n.text("Lets Dock Folders make and update the small app that stands for each folder in the Dock."),
                              granted: model.appManagement) {
                    Permissions.requestAppManagement()
                    model.askedForAppManagement = true
                    model.refresh(checkAppManagement: false)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            if model.askedForAppManagement && !model.appManagement {
                HStack(spacing: 4) {
                    Text(L10n.text("Already turned it on?")).foregroundStyle(.secondary)
                    Button(L10n.text("Check Again")) { model.refresh(checkAppManagement: true) }.buttonStyle(.link)
                    Text(L10n.text("or")).foregroundStyle(.secondary)
                    Button(L10n.text("Reopen Dock Folders")) { Self.relaunch() }.buttonStyle(.link)
                }
                .font(.callout)
                .padding(.top, 10)
            }

            Group {
                if model.accessibility && model.appManagement {
                    Text(L10n.text("All set. To make a folder, drag an app onto another app in the Dock and hold it there."))
                } else {
                    Text(L10n.text("Dock Folders keeps working in the background once these are on."))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
            .padding(.horizontal, 32)

            Button(action: done) {
                Text(L10n.text("Get Started")).frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!(model.accessibility && model.appManagement))
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(width: 460)
        .animation(.default, value: model.accessibility)
        .animation(.default, value: model.appManagement)
    }

    /// Some permissions only reach an app after it restarts.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label(L10n.text("On"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Button(L10n.text("Open Settings…"), action: action)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
