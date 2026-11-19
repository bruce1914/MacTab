import AppKit
import ApplicationServices
import SwiftUI

struct SwitchWindow: Identifiable {
    let id: UUID
    let pid: pid_t
    let element: AXUIElement
    let application: String
    let title: String
    let icon: NSImage?
    var frame: CGRect? = nil
}

@MainActor
final class WindowSwitcherPanel {
    private let panel: NSPanel
    private var hosting: NSHostingView<WindowSwitcherGallery>?
    private var mouseMonitor: Any?
    private var wheelDistance: CGFloat = 0
    private var advance: ((Bool) -> Void)?
    private let previews = WindowPreviews()
    private var session = UUID()
    private var pointerLayout: WindowPreviewLayout?
    private var pointerIDs: [UUID] = []
    private var confirm: ((UUID) -> Void)?

    init() {
        panel = WindowSwitchNativePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("Switch windows")
    }

    func show(_ windows: [SwitchWindow], selected: UUID, available: Set<UUID>,
              session token: UUID? = nil,
              requestPermission: @escaping () -> Void = {}, confirm: @escaping (UUID) -> Void = { _ in },
              advance: @escaping (Bool) -> Void = { _ in }) {
        let screen = (panel.isVisible ? panel.screen : nil)
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        if let token { session = token }
        let index = windows.firstIndex { $0.id == selected } ?? 0
        let layout = WindowPreviewLayout(count: windows.count, selectedIndex: index, screen: frame.size)
        let page = Array(windows[layout.range])
        if !panel.isVisible {
            panel.setFrame(CGRect(x: frame.midX - layout.size.width / 2, y: frame.midY - layout.size.height / 2,
                                  width: layout.size.width, height: layout.size.height), display: false)
        }
        previews.show(windows, session: session, visible: page.map(\.id), selected: selected)
        pointerLayout = layout
        pointerIDs = page.map(\.id)
        self.confirm = confirm
        let root = WindowSwitcherGallery(windows: page, selected: selected, available: available,
            layout: layout, total: windows.count, previews: previews, requestPermission: requestPermission)
        if let hosting { hosting.rootView = root }
        else {
            let hosting = NSHostingView(rootView: root)
            self.hosting = hosting
            panel.contentView = hosting
        }
        self.advance = advance
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
                guard let self, self.panel.isVisible, event.window === self.panel else { return event }
                if event.type == .leftMouseDown {
                    let point = event.locationInWindow
                    let local = CGPoint(x: point.x, y: self.panel.frame.height - point.y)
                    guard let index = self.pointerLayout?.index(at: local, count: self.pointerIDs.count) else { return event }
                    self.confirm?(self.pointerIDs[index])
                    return nil
                }
                guard event.momentumPhase.isEmpty else { return nil }
                if event.phase.contains(.began) { self.wheelDistance = 0 }
                let delta = event.scrollingDeltaY
                guard delta != 0 else { return nil }
                if event.hasPreciseScrollingDeltas {
                    if delta * self.wheelDistance < 0 { self.wheelDistance = 0 }
                    self.wheelDistance += delta
                    guard abs(self.wheelDistance) >= 18 else { return nil }
                    self.wheelDistance = 0
                }
                self.advance?(delta > 0)
                return nil
            }
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        wheelDistance = 0
        advance = nil
        panel.orderOut(nil)
        panel.contentView = nil
        hosting = nil
        pointerLayout = nil
        pointerIDs.removeAll()
        confirm = nil
        previews.end()
        session = UUID()
    }
}

private final class WindowSwitchNativePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct WindowSwitcherGallery: View {
    let windows: [SwitchWindow]
    let selected: UUID
    let available: Set<UUID>
    let layout: WindowPreviewLayout
    let total: Int
    @ObservedObject var previews: WindowPreviews
    let requestPermission: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("MacTab").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(layout.columns > 1 ? "Click or release ⌘ to switch · Esc to cancel" : "Esc to cancel")
                    .font(.system(size: 11)).foregroundStyle(MacTabTheme.secondary).lineLimit(1)
            }
            .frame(height: 18)
            VStack(spacing: WindowPreviewLayout.spacing) {
                ForEach(0..<Int(ceil(Double(windows.count) / Double(layout.columns))), id: \.self) { row in
                    HStack(spacing: WindowPreviewLayout.spacing) {
                        ForEach(Array(windows.dropFirst(row * layout.columns).prefix(layout.columns))) { window in
                            WindowPreviewCard(window: window, image: previews.image(for: window.id),
                                selected: window.id == selected, available: available.contains(window.id))
                                .frame(width: layout.cardWidth, height: WindowPreviewLayout.cardHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: layout.gridHeight)
            HStack {
                Text("\(layout.range.lowerBound + 1)–\(layout.range.upperBound) / \(total)")
                    .font(.system(size: 11).monospacedDigit())
                Spacer()
                if previews.needsPermission {
                    Button("Enable previews", action: requestPermission)
                        .buttonStyle(.borderless).foregroundStyle(MacTabTheme.accent)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(MacTabTheme.secondary)
            .frame(height: 14)
        }
        .padding(16)
        .frame(width: layout.size.width, height: layout.size.height)
        .background(MacTabTheme.background, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(MacTabTheme.text).preferredColorScheme(.light)
    }
}

private struct WindowPreviewCard: View {
    let window: SwitchWindow
    let image: CGImage?
    let selected: Bool
    let available: Bool
    @State private var hovered = false

    var body: some View {
        let hoverOutline = hovered && available && !selected
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                Text(window.application).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(MacTabTheme.surface)
                if let image, available {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().padding(2)
                } else if let icon = window.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 44, height: 44).opacity(0.65)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Text(available ? window.title : "Window closed")
                .font(.system(size: 11)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28, alignment: .topLeading)
        }
        .padding(9)
        .background(selected ? MacTabTheme.selection : MacTabTheme.rail, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
            selected ? MacTabTheme.accent : (hoverOutline ? MacTabTheme.secondary.opacity(0.75) : MacTabTheme.rule),
            lineWidth: selected ? 2 : (hoverOutline ? 1.5 : 1)))
        .opacity(available ? 1 : 0.5)
        .onHover { hovered = $0 }
    }
}
