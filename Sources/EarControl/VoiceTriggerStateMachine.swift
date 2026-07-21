struct VoiceTriggerStateMachine {
    static let restartDelay = 0.08

    enum State: Equatable {
        case idle
        case held
        case restartPending
    }

    enum Command: Equatable {
        case press
        case release
        case cancelScheduledRestart
        case scheduleRestart
    }

    private(set) var state: State = .idle

    var isEngaged: Bool { state != .idle }

    mutating func startOrRestart() -> [Command] {
        switch state {
        case .idle:
            state = .held
            return [.press]
        case .held:
            state = .restartPending
            return [.release, .scheduleRestart]
        case .restartPending:
            return [.cancelScheduledRestart, .scheduleRestart]
        }
    }

    mutating func restartDelayElapsed() -> [Command] {
        guard state == .restartPending else { return [] }
        state = .held
        return [.press]
    }

    mutating func cancel() -> [Command] {
        defer { state = .idle }
        switch state {
        case .idle:
            return []
        case .held:
            return [.release]
        case .restartPending:
            return [.cancelScheduledRestart]
        }
    }
}
