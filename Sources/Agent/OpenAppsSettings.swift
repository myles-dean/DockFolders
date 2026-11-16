import AppKit
import SwiftUI

/// Settings → General: "Open apps only in their folders" — a drop-down that says in a few lines
/// why it needs System Integrity Protection partly off, how to do that, and the switch itself.
struct OpenAppsSection: View {
    @StateObject private var model = OpenAppsModel()
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("macOS gives every open app its own Dock icon, and only the Dock itself can leave one out. With System Integrity Protection (SIP) partly off, Dock Folders can do that from inside the Dock, so an open app shows only in its folder. SIP helps protect your Mac from malware; only turn it off if you’re comfortable with less of that protection."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !model.readiness.ready { steps }

                    Toggle(L10n.text("Show open apps only in their folders"), isOn: Binding(
                        get: { model.enabled },
                        set: { on in
                            OpenAppsInFolders.setEnabled(on)
                            model.refresh()
                        }))
                        .disabled(!model.readiness.ready && !model.enabled)

                    if model.enabled { status }

                    if model.helperInstalled || model.readiness.filesystemOff || model.readiness.debuggingOff {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.text(model.readiness.appleSilicon
                                ? "To turn SIP back on, run `csrutil enable` in Recovery and `sudo nvram -d boot-args` on your Mac."
                                : "To turn SIP back on, run `csrutil enable` in Recovery."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if model.helperInstalled {
                                Button(L10n.text("Remove Helper…")) {
                                    OpenAppsInFolders.uninstallHelper()
                                    model.refresh()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            } label: {
                LabeledContent(L10n.text("Open apps only in their folders")) {
                    Text(model.summary).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var steps: some View {
        let r = model.readiness
        VStack(alignment: .leading, spacing: 10) {
            StepRow(number: 1, done: r.filesystemOff && r.debuggingOff,
                    text: r.appleSilicon
                        ? L10n.text("Shut down. Press and hold the power button until you see startup options, choose Options, then Utilities ▸ Terminal.")
                        : L10n.text("Restart while holding ⌘R, then choose Utilities ▸ Terminal."))
            StepRow(number: 2, done: r.filesystemOff && r.debuggingOff, text: L10n.text("Run this, then restart:"),
                    command: "csrutil enable --without fs --without debug --without nvram")
            if r.appleSilicon {
                StepRow(number: 3, done: r.bootArgSet, text: L10n.text("Back on your Mac, run this in Terminal, then restart again:"),
                        command: "sudo nvram boot-args=-arm64e_preview_abi")
            }
            StepRow(number: r.appleSilicon ? 4 : 3, done: false, text: L10n.text("Come back here and turn it on."))
        }
    }

    @ViewBuilder private var status: some View {
        if let reason = model.pausedReason {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.format("Paused. %@", L10n.text(reason)), systemImage: "pause.circle")
                Spacer()
                Button(L10n.text("Try Again")) { OpenAppsInFolders.setEnabled(true); model.refresh() }
            }
            .font(.callout)
        } else if model.helperInstalled, !model.helperCurrent {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.text("The helper is from another version of Dock Folders."), systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Button(L10n.text("Update…")) { OpenAppsInFolders.setEnabled(true); model.refresh() }
            }
            .font(.callout)
        } else if model.active {
            Label(L10n.text("Working: open apps in folders have no Dock icon of their own."), systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.secondary)
        } else if model.unsupportedDock {
            Label(L10n.text("This version of macOS changed the Dock in a way Dock Folders doesn’t know yet, so it’s leaving the Dock alone."),
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Label(L10n.text("Waiting for the Dock…"), systemImage: "hourglass")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let done: Bool
    let text: String
    var command: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let command {
                    HStack(spacing: 6) {
                        Text(command)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("Copy"))
                    }
                }
            }
        }
    }
}

final class OpenAppsModel: ObservableObject {
    @Published var readiness = OpenAppsInFolders.readiness
    @Published var enabled = OpenAppsInFolders.enabled
    @Published var helperInstalled = false
    @Published var helperCurrent = false
    @Published var active = false
    @Published var unsupportedDock = false
    @Published var pausedReason: String?

    private var observer: NSObjectProtocol?
    private var timer: Timer?

    init() {
        observer = NotificationCenter.default.addObserver(forName: OpenAppsInFolders.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        // The Dock reports in a second or two after it's turned on (or after it restarts).
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.enabled, !self.active else { return }
            self.refresh()
        }
        refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        timer?.invalidate()
    }

    func refresh() {
        readiness = OpenAppsInFolders.readiness
        enabled = OpenAppsInFolders.enabled
        helperInstalled = OpenAppsInFolders.helperInstalled
        helperCurrent = OpenAppsInFolders.helperCurrent
        active = OpenAppsInFolders.isActive
        unsupportedDock = OpenAppsInFolders.loadedButUnhooked
        pausedReason = OpenAppsInFolders.pausedReason?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var summary: String {
        if enabled { return active ? L10n.text("On") : L10n.text("On, not running") }
        return readiness.ready ? L10n.text("Off") : L10n.text("Needs SIP partly off")
    }
}
