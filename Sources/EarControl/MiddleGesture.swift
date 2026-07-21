import Foundation

enum MiddleGesture: String, CaseIterable, Codable, Identifiable {
    case single
    case double
    case triple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "单击"
        case .double: "双击"
        case .triple: "三击"
        }
    }

    var compactTitle: String {
        switch self {
        case .single: "单"
        case .double: "双"
        case .triple: "三"
        }
    }
}

enum MiddleGestureRecognition: Equatable {
    case gesture(MiddleGesture)
    case longPress
}

struct MiddleGestureRecognizer {
    static let clickWindow: TimeInterval = 0.35
    static let longPressThreshold: TimeInterval = 0.8

    private(set) var tapCount = 0
    private(set) var pressStartedAt: TimeInterval?
    private(set) var pendingDeadline: TimeInterval?

    mutating func press(at timestamp: TimeInterval) {
        pendingDeadline = nil
        pressStartedAt = timestamp
    }

    mutating func release(at timestamp: TimeInterval) -> MiddleGestureRecognition? {
        guard let startedAt = pressStartedAt else { return nil }
        pressStartedAt = nil

        if timestamp - startedAt >= Self.longPressThreshold {
            reset()
            return .longPress
        }

        tapCount += 1
        if tapCount >= 3 {
            reset()
            return .gesture(.triple)
        }

        pendingDeadline = timestamp + Self.clickWindow
        return nil
    }

    mutating func flush(at timestamp: TimeInterval) -> MiddleGestureRecognition? {
        guard let deadline = pendingDeadline, timestamp >= deadline else { return nil }
        let gesture: MiddleGesture = tapCount == 2 ? .double : .single
        reset()
        return .gesture(gesture)
    }

    mutating func reset() {
        tapCount = 0
        pressStartedAt = nil
        pendingDeadline = nil
    }
}
