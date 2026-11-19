import Foundation

struct WindowSwitchSession {
    let token = UUID()
    private(set) var windows: [UUID]
    private(set) var index: Int

    init?(windows: [UUID], backwards: Bool) {
        guard !windows.isEmpty else { return nil }
        self.windows = windows
        index = backwards ? windows.count - 1 : min(1, windows.count - 1)
    }

    var selected: UUID { windows[index] }

    mutating func advance(backwards: Bool) {
        index = (index + (backwards ? windows.count - 1 : 1)) % windows.count
    }

    // Keep the gesture order, choosing the next surviving window if selection disappears.
    mutating func retain(_ available: Set<UUID>) -> Bool {
        let remaining = windows.filter { available.contains($0) }
        guard !remaining.isEmpty else { return false }
        let next = (Array(windows[index...]) + Array(windows[..<index])).first { available.contains($0) }!
        windows = remaining
        index = windows.firstIndex(of: next)!
        return true
    }

    @discardableResult
    mutating func select(_ window: UUID) -> Bool {
        guard let position = windows.firstIndex(of: window), position != index else { return false }
        index = position
        return true
    }
}
