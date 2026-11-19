import AppKit
import ApplicationServices
import Carbon


@MainActor
final class WindowSwitcher: ObservableObject {
    @Published private(set) var wanted = false
    @Published private(set) var status = "Paused · Using macOS Command + Tab"
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var catalog: WindowCatalog?
    private var catalogGeneration = UUID()
    private var cached: [SwitchWindow] = []
    private var frozen: [SwitchWindow] = []
    private var session: WindowSwitchSession?
    private var panel: WindowSwitcherPanel?
    private var presentation: DispatchWorkItem?
    private var panelVisible = false
    private var pendingTarget: UUID?
    private var tabDown = false
    private var escapeDown = false
    private var trusted = false
    private var secure = false
    private var blocked = false
    private var waitingForCommandRelease = false
    private var refreshing = false
    private var workspaceTokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var activationFailure: String?
    private var allowsShortcut = true
    private var expectedTapDisable = false

    nonisolated static func handlesShortcuts(for bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return true }
        return !bundleIdentifier.hasPrefix("com.parallels.")
    }

    func start() {
        if UserDefaults.standard.bool(forKey: "WindowSwitcherEnabled") { setEnabled(true) }
    }

    func setEnabled(_ enabled: Bool) {
        wanted = enabled
        UserDefaults.standard.set(enabled, forKey: "WindowSwitcherEnabled")
        blocked = false
        waitingForCommandRelease = false
        stopListening()
        timer?.invalidate()
        timer = nil
        if enabled {
            pulse()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulse() }
            }
        } else { describe("Paused · Using macOS Command + Tab") }
    }

    func shutdown() { timer?.invalidate(); timer = nil; stopListening() }

    func openPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openPreviewPermissions() {
        cancel()
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func describe(_ message: String) { if status != message { status = message } }

    private func pulse() {
        guard wanted else { return }
        trusted = AXIsProcessTrusted()
        secure = IsSecureEventInputEnabled()
        guard trusted, !secure else {
            stopListening()
            describe(trusted ? "Paused during Secure Input · Using system shortcuts" : "Accessibility permission required · Using system shortcuts")
            return
        }
        updateFrontApplication(NSWorkspace.shared.frontmostApplication)
        guard !blocked else { return }
        if tap == nil { installTap() }
        if allowsShortcut { setTapEnabled(true) }
        refresh()
    }

    private func installTap() {
        updateFrontApplication(NSWorkspace.shared.frontmostApplication)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    Unmanaged<WindowSwitcher>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            blocked = true
            describe("Shortcut unavailable · Check Accessibility permission, then pause and resume")
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        setTapEnabled(allowsShortcut)
        let generation = UUID()
        catalogGeneration = generation
        catalog = WindowCatalog { [weak self] windows in
            guard let self, self.wanted, self.tap != nil, self.catalogGeneration == generation else { return }
            self.refreshing = false
            self.cached = windows
            self.promotePending()
            if self.activationFailure == nil { self.describeEnabled() }
            if self.session != nil { self.drawPanel() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.catalog?.noteFocus() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    let app = (name == NSWorkspace.didActivateApplicationNotification)
                        ? notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                        : NSWorkspace.shared.frontmostApplication
                    self?.updateFrontApplication(app)
                    if name == NSWorkspace.didActivateApplicationNotification { self?.catalog?.noteFocus() }
                    else { self?.refresh() }
                }
            })
        }
    }

    private func updateFrontApplication(_ app: NSRunningApplication?) {
        let allowed = Self.handlesShortcuts(for: app?.bundleIdentifier)
        guard allowed != allowsShortcut else { return }
        allowsShortcut = allowed
        if !allowed {
            cancel()
            pendingTarget = nil
            tabDown = false
            escapeDown = false
        }
        setTapEnabled(allowed && trusted && !secure)
        if activationFailure == nil { describeEnabled() }
    }

    private func describeEnabled() {
        guard !blocked else { return }
        describe(allowsShortcut ? "Enabled · \(cached.count) accessible windows · Command + Tab" : "Using guest shortcuts in Parallels")
    }

    private func setTapEnabled(_ enabled: Bool) {
        guard let tap, CGEvent.tapIsEnabled(tap: tap) != enabled else { return }
        // A deliberate suspension also produces tapDisabledByUserInput; it must not block later resumption.
        if !enabled { expectedTapDisable = true }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    private func refresh() {
        guard tap != nil, !refreshing, let catalog else { return }
        refreshing = true
        catalog.refresh()
    }

    private func stopListening() {
        cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        expectedTapDisable = false
        catalogGeneration = UUID()
        catalog?.stop()
        catalog = nil
        refreshing = false
        cached.removeAll()
        pendingTarget = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { center.removeObserver(token) }
        workspaceTokens.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        activationFailure = nil
        tabDown = false
        escapeDown = false
    }

    // This callback never queries Accessibility or draws a window. Work is deferred until it returns.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput, expectedTapDisable {
            expectedTapDisable = false
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            waitingForCommandRelease = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cancel()
                if type == .tapDisabledByUserInput {
                    self.stopListening(); self.blocked = true
                    self.describe("Shortcut listener stopped · Pause and resume to retry")
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard wanted, trusted, !secure, allowsShortcut else { return Unmanaged.passUnretained(event) }
        if waitingForCommandRelease {
            if type == .flagsChanged && !event.flags.contains(.maskCommand) { waitingForCommandRelease = false }
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if session != nil && !event.flags.contains(.maskCommand) {
                commitSelection()
            }
            return Unmanaged.passUnretained(event)
        }
        guard session != nil || event.flags.contains(.maskCommand) || tabDown || escapeDown else {
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if key == 48, tabDown { tabDown = false; return nil }
            if key == 53, escapeDown { escapeDown = false; return nil }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if key == 53, session != nil {
            session = nil
            escapeDown = true
            DispatchQueue.main.async { [weak self] in if self?.session == nil { self?.cancel() } }
            return nil
        }
        guard key == 48, event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl), !event.flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }
        guard !cached.isEmpty else { return Unmanaged.passUnretained(event) }
        tabDown = true
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
        let reverse = event.flags.contains(.maskShift)
        if session == nil {
            frozen = cached
            session = WindowSwitchSession(windows: frozen.map(\.id), backwards: reverse)
            let token = session?.token
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.session?.token == token else { return }
                self.panelVisible = true
                self.drawPanel()
            }
            presentation?.cancel()
            presentation = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        } else {
            session?.advance(backwards: reverse)
            DispatchQueue.main.async { [weak self] in self?.drawPanel() }
        }
        return nil
    }

    private func drawPanel() {
        guard panelVisible, let session else { return }
        if panel == nil { panel = WindowSwitcherPanel() }
        let rows = frozen.map { old in cached.first { $0.id == old.id } ?? old }
        let token = session.token
        panel?.show(rows, selected: session.selected, available: Set(cached.map(\.id)),
            session: token,
            requestPermission: { [weak self] in self?.openPreviewPermissions() },
            confirm: { [weak self] id in
                guard let self, self.panelVisible, self.session?.token == token,
                      self.cached.contains(where: { $0.id == id }) else { return }
                self.session?.select(id)
                self.commitSelection()
            },
            advance: { [weak self] backwards in
                guard let self, self.panelVisible, self.session?.token == token else { return }
                self.session?.advance(backwards: backwards)
                self.drawPanel()
            })
    }

    private func commitSelection() {
        let target = session?.selected
        pendingTarget = target
        promotePending()
        session = nil
        DispatchQueue.main.async { [weak self] in self?.confirm(target) }
    }

    private func cancel() {
        session = nil
        frozen.removeAll()
        presentation?.cancel()
        presentation = nil
        panel?.hide()
        panelVisible = false
    }

    private func promotePending() {
        guard let pendingTarget, let index = cached.firstIndex(where: { $0.id == pendingTarget }) else { return }
        let window = cached.remove(at: index)
        cached.insert(window, at: 0)
    }

    private func confirm(_ target: UUID?) {
        if session == nil { cancel() }
        guard wanted, tap != nil, let target, target == pendingTarget else { return }
        guard let window = cached.first(where: { $0.id == target }) else {
            pendingTarget = nil
            activationFailure = "The selected window closed · Choose another window"
            describe(activationFailure!)
            return
        }
        catalog?.activate(window) { [weak self] success in
            guard let self, self.wanted, self.pendingTarget == target else { return }
            self.pendingTarget = nil
            if success {
                self.activationFailure = nil
                self.describeEnabled()
            } else {
                self.activationFailure = "Could not focus the selected window · Try again or pause MacTab"
                self.describe(self.activationFailure!)
            }
        }
    }
}

private final class WindowCatalog {
    private let activationLock = NSLock()
    private var activationToken: UUID?
    private let queue = DispatchQueue(label: "app.mactab.windows", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "app.mactab.window-scan", qos: .utility)
    private let activationQueue = DispatchQueue(label: "app.mactab.window-activation", qos: .userInteractive)
    private var windows: [SwitchWindow] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: Set<UUID> = []
    private var order: [UUID: UInt64] = [:]
    private var serial: UInt64 = 0
    private var lastFocus: UUID?
    private var stopped = false
    private let scanLock = NSLock()
    private var scanPending = false
    private let deliver: @MainActor ([SwitchWindow]) -> Void

    init(deliver: @escaping @MainActor ([SwitchWindow]) -> Void) { self.deliver = deliver }

    // AX calls for our own process execute AppKit accessors directly, so they must use the main thread.
    private func onElement<T>(_ element: AXUIElement, _ operation: () -> T) -> T {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == getpid(), !Thread.isMainThread { return DispatchQueue.main.sync(execute: operation) }
        return operation()
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        onElement(element) {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value
        }
    }

    func refresh() {
        let schedule = scanLock.withLock {
            guard !scanPending else { return false }
            scanPending = true
            return true
        }
        guard schedule else { return }
        queue.async { [self] in
            guard !stopped else { scanLock.withLock { scanPending = false }; return }
            let previous = windows
            let previousIDs = Set(previous.map(\.id))
            // Slow or unresponsive applications must not delay focus updates or a user's selection.
            scanQueue.async { [self] in
                let applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited && !$0.isTerminated }
                var found: [SwitchWindow] = []
                for app in applications {
                    let pid = app.processIdentifier
                    let element = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(element, 0.12)
                    var raw: CFTypeRef?
                    let error = onElement(element) {
                        AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw)
                    }
                    if error == .cannotComplete {
                        found.append(contentsOf: previous.filter { $0.pid == pid })
                        continue
                    }
                    guard let list = raw as? [AXUIElement], !list.isEmpty else { continue }
                    let icon = previous.first { $0.pid == pid }?.icon ?? app.icon
                    for window in list {
                        if found.contains(where: { $0.pid == pid && CFEqual($0.element, window) }) { continue }
                        if let described = describeWindow(window, app: app, previous: previous, icon: icon) {
                            found.append(described)
                        }
                    }
                }
                let discovered = found
                queue.async { [self] in
                    defer { scanLock.withLock { scanPending = false } }
                    guard !stopped else { return }
                    merge(discovered, applications: applications, previousIDs: previousIDs)
                }
            }
        }
    }

    func noteFocus() {
        queue.async { [self] in
            guard !stopped else { return }
            if focusFrontmost() { publish() } else { refresh() }
        }
    }

    private func describeWindow(_ element: AXUIElement, app: NSRunningApplication,
                                previous: [SwitchWindow], icon: NSImage?) -> SwitchWindow? {
        AXUIElementSetMessagingTimeout(element, 0.12)
        guard value(element, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
        let title = value(element, kAXTitleAttribute) as? String ?? ""
        let subrole = value(element, kAXSubroleAttribute) as? String ?? ""
        if subrole == "AXSystemFloatingWindow" || subrole == "AXFloatingWindow" { return nil }
        var size = CGSize.zero
        if let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
            if AXValueGetValue(raw as! AXValue, .cgSize, &size) {
                // VNC also exposes zero-area and thin AXUnknown helper windows that cannot receive focus.
                if size.width <= 0 || size.height <= 0 { return nil }
                if subrole == "AXUnknown", size.width < 20 || size.height < 20 { return nil }
            }
        }
        let pid = app.processIdentifier
        if pid == getpid() { return nil }
        let id = previous.first { $0.pid == pid && CFEqual($0.element, element) }?.id ?? UUID()
        var position = CGPoint.zero
        var frame: CGRect?
        if size.width > 0, size.height > 0, let raw = value(element, kAXPositionAttribute),
           CFGetTypeID(raw) == AXValueGetTypeID(), AXValueGetValue(raw as! AXValue, .cgPoint, &position) {
            frame = CGRect(origin: position, size: size)
        }
        return SwitchWindow(id: id, pid: pid, element: element,
            application: app.localizedName ?? "Application", title: title.isEmpty ? "Untitled window" : title, icon: icon, frame: frame)
    }

    private func merge(_ discovered: [SwitchWindow], applications: [NSRunningApplication], previousIDs: Set<UUID>) {
        // A focused window may have been learned while discovery was still running. Keep its identity and rank.
        var found = discovered.map { incoming in
            guard let current = windows.first(where: { $0.pid == incoming.pid && CFEqual($0.element, incoming.element) }) else { return incoming }
            return SwitchWindow(id: current.id, pid: incoming.pid, element: incoming.element,
                application: incoming.application, title: incoming.title, icon: incoming.icon, frame: incoming.frame)
        }
        for recent in windows where !previousIDs.contains(recent.id) {
            if !found.contains(where: { $0.pid == recent.pid && CFEqual($0.element, recent.element) }),
               NSRunningApplication(processIdentifier: recent.pid)?.isTerminated == false,
               value(recent.element, kAXRoleAttribute) as? String == kAXWindowRole { found.append(recent) }
        }
        for window in found {
            if observers[window.pid] == nil { observe(window.pid, element: AXUIElementCreateApplication(window.pid)) }
            if watched.insert(window.id).inserted, let observer = observers[window.pid] {
                for name in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                    onElement(window.element) { AXObserverAddNotification(observer, window.element, name as CFString, Unmanaged.passUnretained(self).toOpaque()) }
                }
            }
        }
        let live = Set(found.map(\.id))
        for old in windows where !live.contains(old.id) {
            if let observer = observers[old.pid] {
                for name in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                    onElement(old.element) { AXObserverRemoveNotification(observer, old.element, name as CFString) }
                }
            }
        }
        watched.formIntersection(live)
        order = order.filter { live.contains($0.key) }
        let pids = Set(applications.map(\.processIdentifier))
        for pid in Array(observers.keys) where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        windows = found
        focusFrontmost()
        publish()
    }

    private func observe(_ pid: pid_t, element: AXUIElement) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            let catalog = Unmanaged<WindowCatalog>.fromOpaque(context).takeUnretainedValue()
            catalog.queue.async { [catalog] in
                guard !catalog.stopped else { return }
                if notification as String == kAXWindowCreatedNotification
                    || notification as String == kAXUIElementDestroyedNotification {
                    catalog.refresh()
                } else if notification as String == kAXTitleChangedNotification {
                    catalog.updateTitle(element)
                } else if catalog.focusFrontmost() { catalog.publish() }
                else { catalog.refresh() }
            }
        }, &observer) == .success, let observer else { return }
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification] {
            onElement(element) { AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque()) }
        }
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func updateTitle(_ element: AXUIElement) {
        guard let index = windows.firstIndex(where: { CFEqual($0.element, element) }) else { refresh(); return }
        let old = windows[index]
        let title = value(element, kAXTitleAttribute) as? String ?? ""
        windows[index] = SwitchWindow(id: old.id, pid: old.pid, element: old.element,
            application: old.application, title: title.isEmpty ? "Untitled window" : title, icon: old.icon, frame: old.frame)
        publish()
    }

    @discardableResult
    private func focusFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.12)
        guard let focused = value(application, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        let window: SwitchWindow
        if let known = windows.first(where: { $0.pid == app.processIdentifier && CFEqual($0.element, element) }) {
            window = known
        } else {
            guard app.activationPolicy != .prohibited,
                  let described = describeWindow(element, app: app, previous: windows,
                    icon: windows.first { $0.pid == app.processIdentifier }?.icon ?? app.icon) else { return false }
            window = described
            windows.append(described)
            if observers[app.processIdentifier] == nil { observe(app.processIdentifier, element: application) }
        }
        if lastFocus != window.id { serial += 1; order[window.id] = serial; lastFocus = window.id }
        return true
    }

    private func publish() {
        let indexed = windows.enumerated().sorted {
            let left = order[$0.element.id, default: 0]
            let right = order[$1.element.id, default: 0]
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
        DispatchQueue.main.async { [deliver] in deliver(indexed) }
    }

    func activate(_ window: SwitchWindow, completion: @escaping @MainActor (Bool) -> Void) {
        let token = UUID()
        activationLock.withLock { activationToken = token }
        activationQueue.async { [self] in
            guard current(token),
                  let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
                DispatchQueue.main.async { completion(false) }; return
            }
            // Validate the exact AX element; never fall back to a different window in the same process.
            guard value(window.element, kAXRoleAttribute) as? String == kAXWindowRole else {
                DispatchQueue.main.async { completion(false) }; return
            }
            DispatchQueue.main.async {
                guard self.current(token) else { return }
                app.unhide()
                app.activate(options: [])
                self.activationQueue.asyncAfter(deadline: .now() + 0.12) { [self] in
                    raise(window, token: token, attempts: 3, completion: completion)
                }
            }
        }
    }

    private func current(_ token: UUID) -> Bool { activationLock.withLock { activationToken == token } }

    private func raise(_ window: SwitchWindow, token: UUID, attempts: Int, completion: @escaping @MainActor (Bool) -> Void) {
        guard current(token) else { return }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        onElement(window.element) {
            // Raising an AX window alone does not make its application active on macOS 14.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
                AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window.element)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        let focused = value(app, kAXFocusedWindowAttribute)
        let success = focused.map { CFEqual($0, window.element) } == true
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        if !success, attempts > 1 {
            activationQueue.asyncAfter(deadline: .now() + 0.12) { [self] in raise(window, token: token, attempts: attempts - 1, completion: completion) }
        } else {
            if success {
                queue.async { [self] in
                    guard !stopped else { return }
                    lastFocus = nil
                    focusFrontmost()
                    publish()
                }
            }
            DispatchQueue.main.async { completion(success) }
        }
    }

    func stop() {
        activationLock.withLock { activationToken = nil }
        queue.async { [self] in
            stopped = true
            for observer in observers.values {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observers.removeAll(); windows.removeAll(); watched.removeAll(); order.removeAll()
        }
    }
}
