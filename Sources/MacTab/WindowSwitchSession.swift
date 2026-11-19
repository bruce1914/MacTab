import Foundation

struct WindowSwitchSession {
    let token = UUID()
    let windows: [UUID]
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

    @discardableResult
    mutating func select(_ window: UUID) -> Bool {
        guard let position = windows.firstIndex(of: window), position != index else { return false }
        index = position
        return true
    }
}
