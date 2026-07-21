enum MenuBarClickTarget: Equatable {
    case setup
    case settings
    case panel
}

func menuBarClickTarget(
    setupAvailable: Bool,
    settingsAvailable: Bool
) -> MenuBarClickTarget {
    if setupAvailable { return .setup }
    if settingsAvailable { return .settings }
    return .panel
}
