import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.hid
import ServiceManagement
import SwiftUI

private let consumerPage = 0x0C
private let usagePlayPause = 0xCD
private let usageVolumeUp = 0xE9
private let usageVolumeDown = 0xEA

private let nxKeyTypeSoundUp = 0
private let nxKeyTypeSoundDown = 1
private let nxKeyTypePlay = 16
private let systemDefinedEventType = CGEventType(rawValue: 14)!

private let keyCodeReturn: CGKeyCode = 36
private let keyCodeA: CGKeyCode = 0
private let keyCodeDelete: CGKeyCode = 51
private let nonCoalescedFlag = CGEventFlags(rawValue: 0x100)
private let voiceModifierDefaultsKey = "voiceModifier"
private let voiceOrganizeDelay: TimeInterval = 1.2
private let secondReturnDelay: TimeInterval = 0.6
private let setupCompletedDefaultsKey = "didCompleteSetupV1"

enum VoiceModifier: String, CaseIterable, Identifiable {
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightOption: "右 Option"
        case .rightCommand: "右 Command"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    var genericFlag: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
    }

    var deviceFlag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)
        case .rightCommand: CGEventFlags(rawValue: 0x10)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let model = EarControlModel()
    private var panelWindow: NSPanel?
    private var lastPanelOrigin: NSPoint?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var remapper: HIDRemapper!
    private var systemStateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["EARCONTROL_UI_PREVIEW"] == "1" {
            showUIPreview()
            return
        }

        buildInterface()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        requestAccessibilityPermission()

        startRemapper()
        refreshSystemState()
        systemStateTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshSystemState()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if !UserDefaults.standard.bool(forKey: setupCompletedDefaultsKey) || !self.model.keyboardControlReady {
                self.openSetupWindow()
            }
        }
    }

    private func startRemapper() {
        remapper = HIDRemapper(
            voiceModifier: selectedVoiceModifier,
            middleGestureMappings: model.middleGestureMappings,
            statusHandler: { [weak self] state in
                DispatchQueue.main.async { self?.setStatus(state) }
            },
            eventHandler: { message in
                NSLog("EarControl action: %@", message)
            },
            hardwareEventHandler: { [weak self] event in
                DispatchQueue.main.async { self?.model.recordHardwareEvent(event) }
            },
            mappedActionHandler: { [weak self] action in
                DispatchQueue.main.async { self?.model.recordMappedAction(action) }
            }
        )
        remapper.start()
    }

    private func showUIPreview() {
        let previewState = ProcessInfo.processInfo.environment["EARCONTROL_PREVIEW_STATE"] ?? "ready"
        model.updateConnection(previewState == "waiting" ? .disconnected : .connectedExclusive)
        model.accessibilityTrusted = previewState != "permission"
        model.eventPostingTrusted = previewState != "permission"
        model.inputMonitoringTrusted = true
        model.microphoneName = "External Microphone"
        model.defaultInputIsWired = true
        model.voiceModifier = .rightOption
        model.middleGestureMappings.double = .selectAllAndDelete
        model.launchAtLogin = false
        if previewState == "listening" {
            model.recordMappedAction(.voiceStarted(.rightOption))
        } else if previewState == "internal-microphone" {
            model.microphoneName = "MacBook Air Microphone"
            model.defaultInputIsWired = false
        }

        let previewScreen = ProcessInfo.processInfo.environment["EARCONTROL_PREVIEW_SCREEN"] ?? "panel"
        if previewScreen == "setup", previewState == "ready" {
            model.seenControls = Set(HardwareControl.allCases)
            model.voiceStartVerified = true
            model.voiceEndVerified = true
            model.sendVerified = true
        }
        let rootView: AnyView
        switch previewScreen {
        case "settings": rootView = AnyView(EarControlSettings(model: model))
        case "setup": rootView = AnyView(EarControlSetupView(model: model))
        default: rootView = AnyView(EarControlPanel(model: model))
        }
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        let showsWindowChrome = previewScreen != "panel"
        window.styleMask = showsWindowChrome ? [.titled, .closable] : [.borderless]
        window.title = previewScreen == "setup" ? "设置 EarControl" : (previewScreen == "settings" ? "EarControl 设置" : "")
        window.backgroundColor = showsWindowChrome ? .windowBackgroundColor : .clear
        window.isOpaque = showsWindowChrome
        window.hasShadow = true
        if previewScreen == "setup" {
            window.setContentSize(NSSize(width: 620, height: 650))
        } else {
            window.setContentSize(previewScreen == "settings" ? NSSize(width: 580, height: 500) : NSSize(width: 376, height: 420))
        }
        window.center()
        window.isReleasedWhenClosed = false
        if ProcessInfo.processInfo.environment["EARCONTROL_PREVIEW_APPEARANCE"] == "dark" {
            window.appearance = NSAppearance(named: .darkAqua)
        } else {
            window.appearance = NSAppearance(named: .aqua)
        }
        previewWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let capturePath = ProcessInfo.processInfo.environment["EARCONTROL_PREVIEW_CAPTURE_PATH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak window] in
                guard let window else { return }
                self?.capturePreview(window: window, path: capturePath)
            }
        }
    }

    private func capturePreview(window: NSWindow, path: String) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemStateTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        remapper?.stop()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        remapper?.handleActiveSpaceChange()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["EARCONTROL_UI_PREVIEW"] != "1" else { return }
        refreshSystemState()
    }

    private func buildInterface() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeMenuBarRemoteImage(color: statusItemColor(for: button))
            button.toolTip = "EarControl"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.voiceModifier = selectedVoiceModifier
        model.middleGestureMappings = MiddleGestureMappingsStore.load()
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.onSelectModifier = { [weak self] modifier in self?.selectVoiceModifier(modifier) }
        model.onSetMiddleGestureAction = { [weak self] gesture, action in
            self?.setMiddleGestureAction(action, for: gesture)
        }
        model.onToggleLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }
        model.onResetMappings = { [weak self] in self?.resetMappings() }
        model.onClearDiagnostics = { [weak self] in self?.clearDiagnostics() }
        model.onOpenWeType = { [weak self] in self?.openWeTypeSettings() }
        model.onOpenAccessibility = { [weak self] in self?.openAccessibilitySettings() }
        model.onOpenInputMonitoring = { [weak self] in self?.openInputMonitoringSettings() }
        model.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        model.onReturnToPanel = { [weak self] in self?.returnToPanel() }
        model.onOpenSetup = { [weak self] in self?.openSetupWindow() }
        model.onRequestAccessibility = { [weak self] in self?.requestAccessibilityAccess() }
        model.onRequestInputMonitoring = { [weak self] in self?.requestInputMonitoringAccess() }
        model.onCompleteSetup = { [weak self] in self?.completeSetup() }
        model.onDismissSetup = { [weak self] in self?.dismissSetup() }
        model.onQuit = { NSApplication.shared.terminate(nil) }

        panelWindow = makePanelWindow()
    }

    private func setStatus(_ state: HIDConnectionState) {
        NSLog("EarControl status: %@", state.diagnosticTitle)
        model.updateConnection(state)
        updateStatusItemAppearance()
        statusItem.button?.toolTip = "EarControl · \(state.diagnosticTitle)"
    }

    private func refreshSystemState() {
        let wasReady = model.keyboardControlReady
        let snapshot = AudioInputInspector.snapshot()
        model.microphoneName = snapshot.defaultInputName
        model.defaultInputIsWired = snapshot.defaultInputIsWired
        model.accessibilityTrusted = AXIsProcessTrusted()
        model.eventPostingTrusted = CGPreflightPostEventAccess()
        model.inputMonitoringTrusted = CGPreflightListenEventAccess()
        updateStatusItemAppearance()

        if !wasReady && model.keyboardControlReady, remapper != nil {
            remapper.stop()
            startRemapper()
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        model.accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        model.eventPostingTrusted = CGRequestPostEventAccess()
    }

    private func requestAccessibilityAccess() {
        requestAccessibilityPermission()
        openAccessibilitySettings()
        refreshSystemState()
    }

    private func requestInputMonitoringAccess() {
        model.inputMonitoringTrusted = CGRequestListenEventAccess()
        openInputMonitoringSettings()
        refreshSystemState()
    }

    private func statusItemColor(for button: NSStatusBarButton) -> NSColor {
        // The menu bar may use a dark vibrant appearance over a dark wallpaper
        // even while the rest of macOS is in Light Mode. Resolve against the
        // status item's own window instead of the application's global theme.
        let appearance = button.window?.effectiveAppearance ?? button.effectiveAppearance
        let match = appearance.bestMatch(from: [
            .vibrantDark,
            .darkAqua,
            .vibrantLight,
            .aqua,
        ])
        return match == .vibrantDark || match == .darkAqua ? .white : .black
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        button.contentTintColor = nil
        button.image = makeMenuBarRemoteImage(color: statusItemColor(for: button))
    }

    private func resetMappings() {
        remapper?.releaseAllKeys()
        UserDefaults.standard.set(VoiceModifier.rightOption.rawValue, forKey: voiceModifierDefaultsKey)
        MiddleGestureMappingsStore.save(.defaults)
        remapper?.setVoiceModifier(.rightOption)
        remapper?.setMiddleGestureMappings(.defaults)
        model.voiceModifier = .rightOption
        model.middleGestureMappings = .defaults
        model.recordMappedAction(.mappingsReset)
    }

    private var selectedVoiceModifier: VoiceModifier {
        guard let raw = UserDefaults.standard.string(forKey: voiceModifierDefaultsKey),
              let modifier = VoiceModifier(rawValue: raw) else { return .rightOption }
        return modifier
    }

    private func selectVoiceModifier(_ modifier: VoiceModifier) {
        UserDefaults.standard.set(modifier.rawValue, forKey: voiceModifierDefaultsKey)
        remapper?.setVoiceModifier(modifier)
        model.voiceModifier = modifier
        model.recordMappedAction(.modifierChanged(modifier))
    }

    private func setMiddleGestureAction(_ action: MiddleGestureAction?, for gesture: MiddleGesture) {
        var mappings = model.middleGestureMappings
        mappings[gesture] = action
        MiddleGestureMappingsStore.save(mappings)
        remapper?.setMiddleGestureMappings(mappings)
        model.middleGestureMappings = mappings
        model.recordMappedAction(.middleMappingChanged(gesture, action))
    }

    private func clearDiagnostics() {
        model.clearDiagnostics()
    }

    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            model.issueMessage = nil
            model.launchAtLogin = service.status == .enabled
        } catch {
            model.reportIssue("登录启动设置失败：\(error.localizedDescription)")
            model.launchAtLogin = service.status == .enabled
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        let target = menuBarClickTarget(
            setupAvailable: isWindowAvailable(setupWindow),
            settingsAvailable: isWindowAvailable(settingsWindow)
        )
        switch target {
        case .setup:
            panelWindow?.orderOut(sender)
            if let setupWindow { bringPrimaryWindowForward(setupWindow) }
            return
        case .settings:
            panelWindow?.orderOut(sender)
            if let settingsWindow { bringPrimaryWindowForward(settingsWindow) }
            return
        case .panel:
            break
        }

        guard let panelWindow else { return }
        if panelWindow.isVisible {
            lastPanelOrigin = panelWindow.frame.origin
            panelWindow.orderOut(sender)
        } else {
            model.launchAtLogin = SMAppService.mainApp.status == .enabled
            positionPanel(panelWindow, below: sender)
            lastPanelOrigin = panelWindow.frame.origin
            panelWindow.makeKeyAndOrderFront(sender)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isWindowAvailable(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    private func bringPrimaryWindowForward(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanelWindow() -> NSPanel {
        let controller = NSHostingController(rootView: EarControlPanel(model: model))
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 20
        controller.view.layer?.cornerCurve = .continuous
        controller.view.layer?.masksToBounds = true
        let window = NSPanel(contentViewController: controller)
        window.styleMask = [.borderless, .nonactivatingPanel]
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 376, height: 420))
        return window
    }

    private func positionPanel(_ panel: NSPanel, below sender: NSStatusBarButton) {
        guard let buttonWindow = sender.window else { return }
        let buttonFrameInWindow = sender.convert(sender.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        let panelSize = panel.frame.size
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(
            max(buttonFrame.midX - panelSize.width / 2, screenFrame.minX + 8),
            screenFrame.maxX - panelSize.width - 8
        )
        let y = max(buttonFrame.minY - panelSize.height - 6, screenFrame.minY + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionPanelAtScreenTop(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let panelSize = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: screenFrame.maxX - panelSize.width - 16,
            y: screenFrame.maxY - panelSize.height - 8
        ))
    }

    private func returnToPanel() {
        settingsWindow?.orderOut(nil)
        guard let panelWindow else { return }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let lastPanelOrigin,
           NSScreen.screens.contains(where: {
               $0.visibleFrame.intersects(NSRect(origin: lastPanelOrigin, size: panelWindow.frame.size))
           }) {
            panelWindow.setFrameOrigin(lastPanelOrigin)
        } else if let button = statusItem.button, button.window != nil {
            positionPanel(panelWindow, below: button)
            lastPanelOrigin = panelWindow.frame.origin
        } else {
            positionPanelAtScreenTop(panelWindow)
            lastPanelOrigin = panelWindow.frame.origin
        }
        panelWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        if let panelWindow, panelWindow.isVisible {
            lastPanelOrigin = panelWindow.frame.origin
        }
        panelWindow?.orderOut(nil)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: EarControlSettings(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "EarControl 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 580, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSetupWindow() {
        panelWindow?.orderOut(nil)
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: EarControlSetupView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "设置 EarControl"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 650))
        window.center()
        window.isReleasedWhenClosed = false
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissSetup() {
        setupWindow?.orderOut(nil)
    }

    private func completeSetup() {
        guard model.setupReady else { return }
        UserDefaults.standard.set(true, forKey: setupCompletedDefaultsKey)
        dismissSetup()
    }

    private func openWeTypeSettings() {
        let path = "/Library/Input Methods/WeType.app/Contents/MacOS/WeTypeSettings.app"
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error {
                NSLog("EarControl WeType settings error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self?.model.reportIssue("无法打开微信输入法设置：\(error.localizedDescription)")
                }
            } else {
                DispatchQueue.main.async { self?.model.issueMessage = nil }
            }
        }
    }

    private func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

private func hidInputCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<HIDRemapper>.fromOpaque(context).takeUnretainedValue().receive(value)
}

private func hidDeviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<HIDRemapper>.fromOpaque(context).takeUnretainedValue().deviceChanged(device, added: true)
}

private func hidDeviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDRemapper>.fromOpaque(context).takeUnretainedValue().deviceChanged(device, added: false)
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<HIDRemapper>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        owner.reenableEventTap()
        return Unmanaged.passUnretained(event)
    }

    if type == systemDefinedEventType, owner.shouldSuppress(event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

final class HIDRemapper {
    private var voiceModifier: VoiceModifier
    private var middleGestureMappings: MiddleGestureMappings
    private let statusHandler: (HIDConnectionState) -> Void
    private let eventHandler: (String) -> Void
    private let hardwareEventHandler: (HardwareEvent) -> Void
    private let mappedActionHandler: (MappedAction) -> Void
    private var manager: IOHIDManager?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var targetDeviceIDs = Set<UInt>()
    private var pressedStates: [Int: Bool] = [:]
    private var recentTransitions: [Int: TimeInterval] = [:]
    private var voiceTriggerStateMachine = VoiceTriggerStateMachine()
    private var voiceRestartWorkItem: DispatchWorkItem?
    private var middleGestureRecognizer = MiddleGestureRecognizer()
    private var middleGestureWorkItem: DispatchWorkItem?
    private var hasExclusiveControl = false
    private lazy var hardwareEventSource = CGEventSource(stateID: .hidSystemState)

    fileprivate init(
        voiceModifier: VoiceModifier,
        middleGestureMappings: MiddleGestureMappings,
        statusHandler: @escaping (HIDConnectionState) -> Void,
        eventHandler: @escaping (String) -> Void,
        hardwareEventHandler: @escaping (HardwareEvent) -> Void,
        mappedActionHandler: @escaping (MappedAction) -> Void
    ) {
        self.voiceModifier = voiceModifier
        self.middleGestureMappings = middleGestureMappings
        self.statusHandler = statusHandler
        self.eventHandler = eventHandler
        self.hardwareEventHandler = hardwareEventHandler
        self.mappedActionHandler = mappedActionHandler
    }

    deinit { stop() }

    func start() {
        let hasExclusiveControl = startHIDManager()
        if !hasExclusiveControl {
            startEventTap()
        }
    }

    func stop() {
        releaseAllKeys()

        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    @discardableResult
    private func startHIDManager() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: consumerPage,
            kIOHIDDeviceUsageKey as String: 1,
            kIOHIDProductKey as String: "Headset",
            kIOHIDManufacturerKey as String: "Apple",
            kIOHIDTransportKey as String: "Audio"
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let seizeResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seizeResult == kIOReturnSuccess {
            hasExclusiveControl = true
            refreshTargetDevices()
            return true
        }

        hasExclusiveControl = false
        let fallbackResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if fallbackResult == kIOReturnSuccess {
            refreshTargetDevices(exclusive: false)
        } else {
            statusHandler(.unreadable)
        }
        return false
    }

    private func startEventTap() {
        let mask = CGEventMask(1) << systemDefinedEventType.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: context
        ) else {
            statusHandler(.accessibilityRequired)
            return
        }

        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func reenableEventTap() {
        releaseAllKeys()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    func deviceChanged(_ device: IOHIDDevice, added: Bool) {
        guard isTargetDevice(device) else { return }
        let id = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        if added {
            targetDeviceIDs.insert(id)
            statusHandler(hasExclusiveControl ? .connectedExclusive : .connectedFallback)
        } else {
            targetDeviceIDs.remove(id)
            releaseAllKeys()
            pressedStates.removeAll()
            statusHandler(targetDeviceIDs.isEmpty ? .disconnected : (hasExclusiveControl ? .connectedExclusive : .connectedFallback))
        }
    }

    private func refreshTargetDevices(exclusive: Bool = true) {
        guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            statusHandler(.disconnected)
            return
        }
        for device in devices where isTargetDevice(device) {
            targetDeviceIDs.insert(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
        }
        if targetDeviceIDs.isEmpty {
            statusHandler(.disconnected)
        } else {
            statusHandler(exclusive ? .connectedExclusive : .connectedFallback)
        }
    }

    private func property(_ key: CFString, of device: IOHIDDevice) -> String {
        (IOHIDDeviceGetProperty(device, key) as? String) ?? ""
    }

    private func isTargetDevice(_ device: IOHIDDevice) -> Bool {
        let product = property(kIOHIDProductKey as CFString, of: device).lowercased()
        let manufacturer = property(kIOHIDManufacturerKey as CFString, of: device).lowercased()
        let transport = property(kIOHIDTransportKey as CFString, of: device).lowercased()
        return product == "headset" && manufacturer.contains("apple") && transport == "audio"
    }

    func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == consumerPage else { return }
        let device = IOHIDElementGetDevice(element)
        let deviceID = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        guard targetDeviceIDs.contains(deviceID) else { return }

        let usage = Int(IOHIDElementGetUsage(element))
        guard usage == usagePlayPause || usage == usageVolumeDown || usage == usageVolumeUp else { return }
        let rawValue = IOHIDValueGetIntegerValue(value)
        let pressed = rawValue != 0
        hardwareEventHandler(HardwareEvent(
            control: hardwareControl(for: usage),
            phase: pressed ? .pressed : .released,
            rawValue: rawValue,
            timestamp: Date()
        ))

        // Refresh suppression timing even for repeated held reports, but only
        // execute the mapped action on a real state transition.
        recentTransitions[transitionKey(usage: usage, pressed: pressed)] = ProcessInfo.processInfo.systemUptime
        let previous = pressedStates[usage] ?? false
        guard previous != pressed else { return }
        pressedStates[usage] = pressed

        switch usage {
        case usageVolumeDown:
            if pressed {
                guard canPostKeyboardEvents() else { return }
                startOrRestartVoice()
            }
        case usagePlayPause:
            if pressed {
                guard canPostKeyboardEvents() else { return }
                middleGestureWorkItem?.cancel()
                middleGestureWorkItem = nil
                middleGestureRecognizer.press(at: ProcessInfo.processInfo.systemUptime)
                let wasVoiceActive = voiceTriggerStateMachine.isEngaged
                cancelVoiceTrigger()
                eventHandler("中间键按下 → 结束语音并等待手势")
                if wasVoiceActive { mappedActionHandler(.voiceEnded) }
            } else {
                let now = ProcessInfo.processInfo.systemUptime
                if let recognition = middleGestureRecognizer.release(at: now) {
                    handleMiddleGestureRecognition(recognition)
                } else if middleGestureRecognizer.pendingDeadline != nil {
                    scheduleMiddleGestureFlush()
                }
            }
        case usageVolumeUp:
            if pressed {
                guard canPostKeyboardEvents() else { return }
                if voiceTriggerStateMachine.isEngaged {
                    cancelVoiceTrigger()
                    sendReturnTwiceAfterOrganizing()
                    eventHandler("音量加 → 结束语音，整理后 Return ×2")
                    mappedActionHandler(.sendAfterOrganizing)
                } else {
                    sendKeyPress(keyCode: keyCodeReturn)
                    eventHandler("音量加 → Return（发送）")
                    mappedActionHandler(.sent)
                }
            }
        default:
            break
        }
    }

    func shouldSuppress(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return false }
        let data = Int64(nsEvent.data1)
        let mediaKey = Int((data >> 16) & 0xFFFF)
        let state = Int((data >> 8) & 0xFF)
        let pressed = state == 0x0A

        let usage: Int
        switch mediaKey {
        case nxKeyTypePlay: usage = usagePlayPause
        case nxKeyTypeSoundDown: usage = usageVolumeDown
        case nxKeyTypeSoundUp: usage = usageVolumeUp
        default: return false
        }

        guard let timestamp = recentTransitions[transitionKey(usage: usage, pressed: pressed)] else { return false }
        let age = ProcessInfo.processInfo.systemUptime - timestamp
        return age >= 0 && age < 0.35
    }

    func releaseAllKeys() {
        cancelPendingMiddleGesture()
        cancelVoiceTrigger()
        pressedStates[usageVolumeDown] = false
    }

    func handleActiveSpaceChange() {
        guard voiceTriggerStateMachine.isEngaged else { return }
        cancelVoiceTrigger()
        eventHandler("桌面切换 → 释放语音触发键")
        mappedActionHandler(.voiceInterruptedBySpaceChange)
    }

    fileprivate func setVoiceModifier(_ modifier: VoiceModifier) {
        releaseAllKeys()
        voiceModifier = modifier
    }

    fileprivate func setMiddleGestureMappings(_ mappings: MiddleGestureMappings) {
        cancelPendingMiddleGesture()
        middleGestureMappings = mappings
    }

    private func scheduleMiddleGestureFlush() {
        middleGestureWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.middleGestureWorkItem = nil
            guard let recognition = self.middleGestureRecognizer.flush(
                at: ProcessInfo.processInfo.systemUptime
            ) else { return }
            self.handleMiddleGestureRecognition(recognition)
        }
        middleGestureWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MiddleGestureRecognizer.clickWindow,
            execute: workItem
        )
    }

    private func cancelPendingMiddleGesture() {
        middleGestureWorkItem?.cancel()
        middleGestureWorkItem = nil
        middleGestureRecognizer.reset()
    }

    private func handleMiddleGestureRecognition(_ recognition: MiddleGestureRecognition) {
        switch recognition {
        case .longPress:
            guard canPostKeyboardEvents() else { return }
            clearCurrentInput()
            eventHandler("中间键长按 → 全选删除")
            mappedActionHandler(.cleared)
        case .gesture(let gesture):
            let action = middleGestureMappings[gesture]
            if let action {
                guard canPostKeyboardEvents() else { return }
                switch action.kind {
                case .shortcut:
                    if let shortcut = action.recordedShortcut {
                        sendRecordedShortcut(shortcut)
                    }
                case .selectAllAndDelete:
                    clearCurrentInput()
                case .finishVoiceAndSend:
                    sendReturnTwiceAfterOrganizing(
                        finalMappedAction: .middleGesture(gesture, action)
                    )
                }
                eventHandler("中间键\(gesture.title) → \(action.displayTitle)")
            } else {
                eventHandler("中间键\(gesture.title) → 仅结束语音")
            }
            mappedActionHandler(.middleGesture(gesture, action))
        }
    }

    private func transitionKey(usage: Int, pressed: Bool) -> Int {
        usage * 2 + (pressed ? 1 : 0)
    }

    private func hardwareControl(for usage: Int) -> HardwareControl {
        switch usage {
        case usageVolumeUp: .volumeUp
        case usagePlayPause: .middle
        default: .volumeDown
        }
    }

    private func canPostKeyboardEvents() -> Bool {
        let trusted = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        if !trusted {
            eventHandler("映射未执行：需要重新授予辅助功能权限")
        }
        return trusted
    }

    private func startOrRestartVoice() {
        let wasEngaged = voiceTriggerStateMachine.isEngaged
        let commands = voiceTriggerStateMachine.startOrRestart()
        applyVoiceTriggerCommands(commands)

        if wasEngaged {
            eventHandler("音量减 → 重新开始语音（先释放\(voiceModifier.title)）")
            mappedActionHandler(.voiceRestarting(voiceModifier))
        } else {
            eventHandler("音量减 → 开始语音（\(voiceModifier.title)保持按下）")
            mappedActionHandler(.voiceStarted(voiceModifier))
        }
    }

    private func cancelVoiceTrigger() {
        applyVoiceTriggerCommands(voiceTriggerStateMachine.cancel())
    }

    private func applyVoiceTriggerCommands(_ commands: [VoiceTriggerStateMachine.Command]) {
        for command in commands {
            switch command {
            case .press:
                postVoiceModifier(pressed: true)
            case .release:
                postVoiceModifier(pressed: false)
            case .cancelScheduledRestart:
                voiceRestartWorkItem?.cancel()
                voiceRestartWorkItem = nil
            case .scheduleRestart:
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.voiceRestartWorkItem = nil
                    let commands = self.voiceTriggerStateMachine.restartDelayElapsed()
                    guard !commands.isEmpty else { return }
                    self.applyVoiceTriggerCommands(commands)
                    self.eventHandler("音量减 → 已重新开始语音（\(self.voiceModifier.title)保持按下）")
                    self.mappedActionHandler(.voiceRestarted(self.voiceModifier))
                }
                voiceRestartWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + VoiceTriggerStateMachine.restartDelay,
                    execute: workItem
                )
            }
        }
    }

    private func clearCurrentInput() {
        sendShortcut(keyCode: keyCodeA, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.sendKeyPress(keyCode: keyCodeDelete)
        }
    }

    private func sendReturnTwiceAfterOrganizing(finalMappedAction: MappedAction? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + voiceOrganizeDelay) { [weak self] in
            guard let self else { return }
            self.sendKeyPress(keyCode: keyCodeReturn)
            DispatchQueue.main.asyncAfter(deadline: .now() + secondReturnDelay) { [weak self] in
                guard let self else { return }
                self.sendKeyPress(keyCode: keyCodeReturn)
                self.mappedActionHandler(.sent)
                if let finalMappedAction {
                    self.mappedActionHandler(finalMappedAction)
                }
            }
        }
    }

    private func postVoiceModifier(pressed: Bool) {
        guard let event = CGEvent(keyboardEventSource: hardwareEventSource, virtualKey: voiceModifier.keyCode, keyDown: pressed) else { return }
        event.type = .flagsChanged
        event.flags = pressed
            ? CGEventFlags(rawValue: voiceModifier.genericFlag.rawValue | voiceModifier.deviceFlag.rawValue | nonCoalescedFlag.rawValue)
            : nonCoalescedFlag
        event.post(tap: .cghidEventTap)
    }

    private func sendKeyPress(keyCode: CGKeyCode) {
        CGEvent(keyboardEventSource: hardwareEventSource, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: hardwareEventSource, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func sendRecordedShortcut(_ shortcut: RecordedShortcut) {
        switch shortcut.kind {
        case .key:
            sendShortcut(keyCode: CGKeyCode(shortcut.keyCode), flags: shortcut.cgFlags)
        case .modifier:
            guard let genericFlag = shortcut.bareModifierFlags,
                  let deviceFlag = shortcut.bareModifierDeviceFlag,
                  let keyDown = CGEvent(
                    keyboardEventSource: hardwareEventSource,
                    virtualKey: CGKeyCode(shortcut.keyCode),
                    keyDown: true
                  ),
                  let keyUp = CGEvent(
                    keyboardEventSource: hardwareEventSource,
                    virtualKey: CGKeyCode(shortcut.keyCode),
                    keyDown: false
                  )
            else { return }
            keyDown.type = .flagsChanged
            keyDown.flags = CGEventFlags(
                rawValue: genericFlag.rawValue | deviceFlag.rawValue | nonCoalescedFlag.rawValue
            )
            keyUp.type = .flagsChanged
            keyUp.flags = nonCoalescedFlag
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func sendShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard
            let keyDown = CGEvent(keyboardEventSource: hardwareEventSource, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: hardwareEventSource, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

private enum AudioInputInspector {
    struct Snapshot {
        let defaultInputName: String
        let defaultInputIsWired: Bool
    }

    static func snapshot() -> Snapshot {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let defaultInput = objectIDProperty(system, selector: kAudioHardwarePropertyDefaultInputDevice) else {
            return Snapshot(defaultInputName: "不可用", defaultInputIsWired: false)
        }

        let defaultName = stringProperty(defaultInput, selector: kAudioObjectPropertyName) ?? "未知设备"
        return Snapshot(defaultInputName: defaultName, defaultInputIsWired: isWiredInputName(defaultName))
    }

    private static func isWiredInputName(_ value: String) -> Bool {
        let name = value.lowercased()
        return name.contains("earpods")
            || name.contains("headset")
            || name.contains("external microphone")
            || name.contains("usb audio")
            || name.contains("有线")
            || name.contains("外置麦克风")
            || name.contains("耳机麦克风")
    }

    private static func objectIDProperty(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func stringProperty(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeUnretainedValue() as String
    }

}

let earControlApplication = NSApplication.shared
let earControlDelegate = AppDelegate()
earControlApplication.delegate = earControlDelegate
earControlApplication.setActivationPolicy(.accessory)
earControlApplication.run()
