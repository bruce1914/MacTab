import AppKit
import ScreenCaptureKit

struct WindowPreviewCandidate {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
}

enum WindowPreviewMatching {
    static func match(pid: pid_t, title: String, frame: CGRect?, candidates: [WindowPreviewCandidate]) -> CGWindowID? {
        let owned = candidates.filter { $0.pid == pid }
        if let frame {
            let aligned = owned.filter {
                abs($0.frame.minX - frame.minX) <= 2 && abs($0.frame.minY - frame.minY) <= 2
                    && abs($0.frame.width - frame.width) <= 2 && abs($0.frame.height - frame.height) <= 2
            }
            if aligned.count == 1 { return aligned[0].id }
            let named = aligned.filter { !$0.title.isEmpty && $0.title == title }
            return named.count == 1 ? named[0].id : nil
        }
        guard !title.isEmpty, title != "Untitled window" else { return nil }
        let named = owned.filter { $0.title == title }
        return named.count == 1 ? named[0].id : nil
    }
}

struct WindowPreviewCache {
    private var images: [UUID: CGImage] = [:]
    private var order: [UUID] = []
    private(set) var byteCount = 0
    let maximumCount: Int
    let maximumBytes: Int

    init(maximumCount: Int = 16, maximumBytes: Int = 8 * 1024 * 1024) {
        self.maximumCount = max(1, maximumCount)
        self.maximumBytes = max(1, maximumBytes)
    }

    var count: Int { images.count }
    func image(for id: UUID) -> CGImage? { images[id] }

    mutating func touch(_ id: UUID) {
        guard images[id] != nil else { return }
        order.removeAll { $0 == id }
        order.append(id)
    }

    @discardableResult
    mutating func insert(_ image: CGImage, for id: UUID) -> Bool {
        let cost = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !cost.overflow, cost.partialValue <= maximumBytes else { return false }
        remove(id)
        while count >= maximumCount || byteCount + cost.partialValue > maximumBytes {
            guard let oldest = order.first else { break }
            remove(oldest)
        }
        images[id] = image
        order.append(id)
        byteCount += cost.partialValue
        return true
    }

    private mutating func remove(_ id: UUID) {
        if let image = images.removeValue(forKey: id) { byteCount -= image.bytesPerRow * image.height }
        order.removeAll { $0 == id }
    }

    mutating func removeAll() {
        images.removeAll()
        order.removeAll()
        byteCount = 0
    }
}

struct WindowPreviewLayout {
    static let cardHeight: CGFloat = 180
    static let spacing: CGFloat = 12
    let columns: Int
    let capacity: Int
    let cardWidth: CGFloat
    let size: CGSize
    let range: Range<Int>
    var gridHeight: CGFloat { size.height - 88 }

    func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let rows = Int(ceil(Double(count) / Double(columns)))
        let height = CGFloat(rows) * Self.cardHeight + CGFloat(rows - 1) * Self.spacing
        let top = 46 + (gridHeight - height) / 2
        guard point.y >= top else { return nil }
        let row = Int((point.y - top) / (Self.cardHeight + Self.spacing))
        guard row < rows, point.y - top - CGFloat(row) * (Self.cardHeight + Self.spacing) < Self.cardHeight else { return nil }
        let items = min(columns, count - row * columns)
        let width = CGFloat(items) * cardWidth + CGFloat(items - 1) * Self.spacing
        let left = (size.width - width) / 2
        guard point.x >= left else { return nil }
        let column = Int((point.x - left) / (cardWidth + Self.spacing))
        guard column < items, point.x - left - CGFloat(column) * (cardWidth + Self.spacing) < cardWidth else { return nil }
        return row * columns + column
    }

    init(count: Int, selectedIndex: Int, screen: CGSize) {
        let width = max(1, screen.width - 48)
        let maximumColumns = min(5, max(1, min(count, Int((width - 32 + Self.spacing) / (224 + Self.spacing)))))
        let rowLimit = min(3, max(1, Int((screen.height - 96 - 88 + Self.spacing) / (Self.cardHeight + Self.spacing))))
        let pageCount = min(max(0, count), maximumColumns * rowLimit)
        let balancedRows = max(1, Int(ceil(Double(pageCount) / Double(maximumColumns))))
        columns = max(1, min(maximumColumns, Int(ceil(Double(pageCount) / Double(balancedRows)))))
        cardWidth = max(1, min(224, (width - 32 - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns)))
        capacity = columns * rowLimit
        let rows = max(1, Int(ceil(Double(min(max(0, count), capacity)) / Double(columns))))
        size = CGSize(width: CGFloat(columns) * cardWidth + CGFloat(columns - 1) * Self.spacing + 32,
                      height: CGFloat(rows) * Self.cardHeight + CGFloat(rows - 1) * Self.spacing + 88)
        let index = min(max(0, selectedIndex), max(0, count - 1))
        let start = (index / capacity) * capacity
        range = start..<max(start, min(max(0, count), start + capacity))
    }
}

@MainActor
final class WindowPreviews: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var needsPermission = false
    private var cache = WindowPreviewCache()
    private var session: UUID?
    private var windows: [SwitchWindow] = []
    private var visible: Set<UUID> = []
    private var pending: [UUID] = []
    private var failed: Set<UUID> = []
    private var selected: UUID?
    private var contentSession: UUID?
    private var sources: [SCWindow] = []
    private var inFlight: (session: UUID, id: UUID)?
    private var worker: Task<Void, Never>?

    var cachedBytes: Int { cache.byteCount }
    var cachedCount: Int { cache.count }
    func image(for id: UUID) -> CGImage? { cache.image(for: id) }

    func show(_ windows: [SwitchWindow], session: UUID, visible ids: [UUID], selected: UUID) {
        if self.session != session {
            end()
            self.session = session
            needsPermission = !CGPreflightScreenCaptureAccess()
        }
        self.windows = windows
        self.selected = selected
        visible = Set(ids)
        pending.removeAll { !visible.contains($0) }
        for id in ids {
            cache.touch(id)
            if !needsPermission, cache.image(for: id) == nil, !failed.contains(id), !pending.contains(id),
               !(inFlight?.session == session && inFlight?.id == id) { pending.append(id) }
        }
        cache.touch(selected)
        if worker == nil, !pending.isEmpty {
            worker = Task { [weak self] in await self?.capturePending() }
        }
    }

    func end() {
        session = nil
        windows.removeAll()
        visible.removeAll()
        pending.removeAll()
        failed.removeAll()
        sources.removeAll()
        contentSession = nil
        cache.removeAll()
        revision += 1
        // Keep at most one native capture in flight, even across rapidly reopened panels.
        // Its result is discarded after dismissal; a later gesture waits for that operation to finish.
    }

    private func capturePending() async {
        defer { worker = nil }
        while let token = session, !pending.isEmpty {
            if let selected, let index = pending.firstIndex(of: selected) { pending.swapAt(0, index) }
            let id = pending.removeFirst()
            guard visible.contains(id), let window = windows.first(where: { $0.id == id }) else { continue }
            guard CGPreflightScreenCaptureAccess() else {
                needsPermission = true
                pending.removeAll()
                break
            }
            if contentSession != token {
                do {
                    // Offscreen windows can leave a single-frame capture waiting indefinitely.
                    // Keep them in the switcher, but request previews only for onscreen sources.
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    guard session == token else { continue }
                    sources = content.windows
                    contentSession = token
                } catch {
                    guard session == token else { continue }
                    pending.removeAll()
                    needsPermission = !CGPreflightScreenCaptureAccess()
                    break
                }
            }
            let candidates = sources.compactMap { source -> WindowPreviewCandidate? in
                guard source.isOnScreen, let app = source.owningApplication else { return nil }
                return WindowPreviewCandidate(id: source.windowID, pid: app.processID,
                    title: source.title ?? "", frame: source.frame)
            }
            guard let number = WindowPreviewMatching.match(pid: window.pid, title: window.title,
                    frame: window.frame, candidates: candidates),
                  let source = sources.first(where: { $0.windowID == number }) else {
                failed.insert(id)
                continue
            }
            let scale = min(448 / max(1, source.frame.width), 280 / max(1, source.frame.height))
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(source.frame.width * scale))
            configuration.height = max(1, Int(source.frame.height * scale))
            configuration.scalesToFit = true
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            inFlight = (token, id)
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: source), configuration: configuration)
                inFlight = nil
                guard session == token, visible.contains(id) else { continue }
                if cache.insert(image, for: id) { revision += 1 }
                else { failed.insert(id) }
            } catch {
                inFlight = nil
                if session == token { failed.insert(id) }
            }
        }
    }
}
