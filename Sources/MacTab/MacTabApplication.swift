import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum MacTabApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = MacTabDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class MacTabDelegate: NSObject, NSApplicationDelegate {
    private let switcher = WindowSwitcher()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Enable MacTab", action: #selector(toggle), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != getpid() }) {
            running.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "MacTab")
        item.button?.toolTip = "MacTab"
        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        for (title, action) in [("Settings…", #selector(showSettings)),
                                ("Accessibility Permission…", #selector(accessibilityPermission)),
                                ("Preview Permission…", #selector(previewPermission))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacTab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        subscription = switcher.$status.combineLatest(switcher.$wanted).sink { [weak self] status, wanted in
            self?.statusMenuItem.title = status
            self?.toggleMenuItem.title = wanted ? "Pause MacTab" : "Enable MacTab"
        }
        switcher.start()
        if !UserDefaults.standard.bool(forKey: "HasOpenedSettings") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "HasOpenedSettings")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { switcher.shutdown() }

    @objc private func toggle() { switcher.setEnabled(!switcher.wanted) }
    @objc private func accessibilityPermission() { switcher.openPermissions() }
    @objc private func previewPermission() { switcher.openPreviewPermissions() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 470),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "MacTab"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacTabSettings(switcher: switcher))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct MacTabSettings: View {
    @ObservedObject var switcher: WindowSwitcher

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 30)).foregroundStyle(MacTabTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacTab").font(.system(size: 26, weight: .semibold))
                    Text("Windows-style window switching for Mac.").foregroundStyle(MacTabTheme.secondary)
                }
            }
            HStack {
                Text(switcher.status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(switcher.wanted ? "Pause" : "Enable") { switcher.setEnabled(!switcher.wanted) }
                    .buttonStyle(.borderedProminent).tint(MacTabTheme.accent)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions").font(.headline)
                Text("Allow Accessibility to switch windows. Screen Recording is optional and enables thumbnail previews.")
                    .font(.system(size: 12)).foregroundStyle(MacTabTheme.secondary)
                HStack {
                    Button("Accessibility…") { switcher.openPermissions() }
                    Button("Window previews…") { switcher.openPreviewPermissions() }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("How to switch").font(.headline)
                Text("⌘ Tab  Next window     ⌘ ⇧ Tab  Previous window")
                Text("Release Command to switch. Escape to cancel.")
                Text("Hover to highlight. Click a card to switch immediately.")
            }.font(.system(size: 12))
            Text("Parallels keeps its own shortcuts. No tracking, network requests, or automatic login startup.")
                .font(.system(size: 11)).foregroundStyle(MacTabTheme.secondary)
            Spacer(minLength: 0)
        }
        .padding(28).frame(width: 500, height: 470, alignment: .topLeading)
        .foregroundStyle(MacTabTheme.text).background(MacTabTheme.background).preferredColorScheme(.light)
    }
}
