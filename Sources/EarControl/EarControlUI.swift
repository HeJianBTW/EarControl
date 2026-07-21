import AppKit
import SwiftUI

enum HardwareControl: String, CaseIterable, Identifiable, Hashable {
    case volumeUp
    case middle
    case volumeDown

    var id: String { rawValue }

    var diagnosticTitle: String {
        switch self {
        case .volumeUp: "音量加"
        case .middle: "中间键"
        case .volumeDown: "音量减"
        }
    }

}

enum ControlPhase: String {
    case pressed
    case released

    var title: String { self == .pressed ? "按下" : "松开" }
}

struct HardwareEvent: Identifiable {
    let id = UUID()
    let control: HardwareControl
    let phase: ControlPhase
    let rawValue: CFIndex
    let timestamp: Date

    var description: String {
        let time = timestamp.formatted(date: .omitted, time: .standard)
        return "\(control.diagnosticTitle) · \(phase.title) · value \(rawValue) · \(time)"
    }
}

enum MappedAction {
    case voiceStarted(VoiceModifier)
    case voiceRestarting(VoiceModifier)
    case voiceRestarted(VoiceModifier)
    case voiceEnded
    case voiceInterruptedBySpaceChange
    case organizing
    case cleared
    case sendAfterOrganizing
    case sent
    case middleGesture(MiddleGesture, MiddleGestureAction?)
    case middleMappingChanged(MiddleGesture, MiddleGestureAction?)
    case modifierChanged(VoiceModifier)
    case mappingsReset

    var description: String {
        switch self {
        case .voiceStarted(let modifier): "开始语音（\(modifier.title)保持按下）"
        case .voiceRestarting(let modifier): "正在重新开始语音（释放\(modifier.title)）"
        case .voiceRestarted(let modifier): "已重新开始语音（\(modifier.title)保持按下）"
        case .voiceEnded: "结束语音"
        case .voiceInterruptedBySpaceChange: "桌面切换导致语音结束"
        case .organizing: "等待输入法整理"
        case .cleared: "已全选并删除"
        case .sendAfterOrganizing: "结束语音，整理后 Return ×2"
        case .sent: "Return 已发送"
        case .middleGesture(let gesture, let action):
            "中键\(gesture.title) → \(action?.displayTitle ?? "仅结束语音")"
        case .middleMappingChanged(let gesture, let action):
            "\(gesture.title)映射改为\(action?.displayTitle ?? "未设置")"
        case .modifierChanged(let modifier): "语音触发键改为\(modifier.title)"
        case .mappingsReset: "已恢复默认三键映射"
        }
    }
}

enum HIDConnectionState: Equatable {
    case starting
    case disconnected
    case connectedExclusive
    case connectedFallback
    case unreadable
    case accessibilityRequired

    var isConnected: Bool {
        self == .connectedExclusive || self == .connectedFallback
    }

    var diagnosticTitle: String {
        switch self {
        case .starting: "正在启动"
        case .disconnected: "未检测到 Apple 有线耳机"
        case .connectedExclusive: "已连接 · HID 独占拦截"
        case .connectedFallback: "已连接 · 事件过滤回退"
        case .unreadable: "无法读取耳机；请开启输入监控"
        case .accessibilityRequired: "请开启辅助功能权限后重新启动"
        }
    }
}

enum PanelStatus {
    case starting
    case waitingForHeadset
    case needsAccessibility
    case ready
    case error

    var title: String {
        switch self {
        case .starting: "正在启动"
        case .waitingForHeadset: "等待耳机"
        case .needsAccessibility: "需要辅助功能权限"
        case .ready: "线控已接管"
        case .error: "需要处理"
        }
    }
}

final class EarControlModel: ObservableObject {
    @Published var connectionState: HIDConnectionState = .starting
    @Published var accessibilityTrusted = false
    @Published var eventPostingTrusted = false
    @Published var inputMonitoringTrusted = false
    @Published var microphoneName = "检测中…"
    @Published var defaultInputIsWired = false
    @Published var voiceModifier: VoiceModifier = .rightOption
    @Published var middleGestureMappings = MiddleGestureMappings.defaults
    @Published var launchAtLogin = false
    @Published var pressedControl: HardwareControl?
    @Published var voiceActive = false
    @Published var lastHardwareEvent = "尚未收到原始事件"
    @Published var lastMappedAction = "等待耳机按键…"
    @Published var rawEventCount = 0
    @Published var recentEvents: [HardwareEvent] = []
    @Published var seenControls = Set<HardwareControl>()
    @Published var voiceStartVerified = false
    @Published var voiceEndVerified = false
    @Published var sendVerified = false
    @Published var issueMessage: String?

    var onSelectModifier: ((VoiceModifier) -> Void)?
    var onSetMiddleGestureAction: ((MiddleGesture, MiddleGestureAction?) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onResetMappings: (() -> Void)?
    var onClearDiagnostics: (() -> Void)?
    var onOpenWeType: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onReturnToPanel: (() -> Void)?
    var onOpenSetup: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onRequestInputMonitoring: (() -> Void)?
    var onCompleteSetup: (() -> Void)?
    var onDismissSetup: (() -> Void)?
    var onQuit: (() -> Void)?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var panelStatus: PanelStatus {
        if issueMessage != nil { return .error }
        switch connectionState {
        case .starting:
            return .starting
        case .unreadable, .accessibilityRequired:
            return .error
        case .disconnected:
            return .waitingForHeadset
        case .connectedExclusive, .connectedFallback:
            return keyboardControlReady ? .ready : .needsAccessibility
        }
    }

    var keyboardControlReady: Bool {
        accessibilityTrusted && eventPostingTrusted
    }

    var inputMonitoringRequired: Bool {
        connectionState == .connectedFallback || connectionState == .unreadable
    }

    var testedControlCount: Int { seenControls.count }

    var workflowVerified: Bool {
        voiceStartVerified && voiceEndVerified && sendVerified
    }

    var setupReady: Bool {
        connectionState.isConnected
            && keyboardControlReady
            && (!inputMonitoringRequired || inputMonitoringTrusted)
    }

    func updateConnection(_ state: HIDConnectionState) {
        connectionState = state
        if !state.isConnected {
            voiceActive = false
            pressedControl = nil
        }
    }

    func reportIssue(_ message: String) {
        issueMessage = message
    }

    func recordHardwareEvent(_ event: HardwareEvent) {
        rawEventCount += 1
        lastHardwareEvent = event.description
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 20 { recentEvents.removeLast() }
        seenControls.insert(event.control)

        if event.phase == .pressed {
            pressedControl = event.control
        } else if pressedControl == event.control {
            withAnimation(.easeOut(duration: 0.12)) {
                pressedControl = nil
            }
        }
    }

    func recordMappedAction(_ action: MappedAction) {
        lastMappedAction = action.description
        switch action {
        case .voiceStarted, .voiceRestarted:
            voiceActive = true
            voiceStartVerified = true
        case .voiceRestarting:
            voiceActive = false
        case .voiceEnded, .voiceInterruptedBySpaceChange:
            voiceActive = false
            voiceEndVerified = true
        case .organizing, .cleared:
            voiceActive = false
        case .sendAfterOrganizing:
            voiceActive = false
            voiceEndVerified = true
        case .sent:
            voiceActive = false
            sendVerified = true
        case .middleGesture, .middleMappingChanged, .modifierChanged, .mappingsReset:
            break
        }
    }

    func isActive(_ control: HardwareControl) -> Bool {
        pressedControl == control || (voiceActive && control == .volumeDown)
    }

    func clearDiagnostics() {
        lastHardwareEvent = "尚未收到原始事件"
        lastMappedAction = "等待耳机按键…"
        rawEventCount = 0
        recentEvents.removeAll()
        seenControls.removeAll()
        voiceStartVerified = false
        voiceEndVerified = false
        sendVerified = false
    }

    var diagnosticsText: String {
        let events = recentEvents.map(\.description).joined(separator: "\n")
        return """
        EarControl v\(version)
        连接：\(connectionState.diagnosticTitle)
        辅助功能：\(accessibilityTrusted ? "已授权" : "未授权")
        键盘事件发送：\(eventPostingTrusted ? "已允许" : "未允许")
        输入监控：\(inputMonitoringTrusted ? "已允许" : "未允许")\(inputMonitoringRequired ? "（当前需要）" : "（当前可选）")
        当前输入：\(microphoneName)
        有线输入：\(defaultInputIsWired ? "是" : "否")
        最近映射：\(lastMappedAction)
        中键手势：\(middleGestureMappings.compactSummary)
        原始报告：\(rawEventCount) 条
        已检测按键：\(testedControlCount)/3
        完整工作流：\(workflowVerified ? "已通过" : "未完成")

        \(events.isEmpty ? "无原始事件" : events)
        """
    }
}

struct EarControlPanel: View {
    @ObservedObject var model: EarControlModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            remoteWorkflow
                .padding(.top, 20)
            inputStatus
                .padding(.top, 18)
            if model.panelStatus == .needsAccessibility || model.panelStatus == .error {
                issueRow
                    .padding(.top, 10)
            }
            footer
                .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 376)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("EarControl")
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(model.panelStatus.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("状态：\(model.panelStatus.title)")
        }
    }

    private var remoteWorkflow: some View {
        HStack(spacing: 28) {
            RemoteControlView(model: model)
            VStack(alignment: .leading, spacing: 0) {
                MappingDescription(
                    title: "结束并发送",
                    detail: "自动整理输入",
                    active: model.isActive(.volumeUp)
                )
                MiddleGestureSummary(
                    mappings: model.middleGestureMappings,
                    active: model.isActive(.middle)
                )
                MappingDescription(
                    title: "开始说话",
                    detail: model.voiceModifier == .rightOption ? "右 ⌥" : "右 ⌘",
                    active: model.isActive(.volumeDown)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("三键线控映射")
        .accessibilityValue("音量加：结束并发送；中间键：单击、双击和三击可自定义，长按清空；音量减：使用\(model.voiceModifier.title)开始说话")
    }

    private var inputStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.defaultInputIsWired ? Color.secondary : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前输入")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.microphoneName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !model.defaultInputIsWired && model.microphoneName != "检测中…" {
                    Text("语音可能使用 MacBook 或其他设备的麦克风")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var issueRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(model.issueMessage ?? model.connectionState.diagnosticTitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button(model.panelStatus == .needsAccessibility ? "打开权限…" : "处理…") {
                model.onOpenSetup?()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("登录时启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: { _ in model.onToggleLaunchAtLogin?() }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            Spacer()
            Button("设置…") { model.onOpenSettings?() }
                .controlSize(.small)
            Button("退出") { model.onQuit?() }
                .controlSize(.small)
        }
    }

    private var statusColor: Color {
        switch model.panelStatus {
        case .ready: .green
        case .needsAccessibility, .error: .orange
        case .starting, .waitingForHeadset: .secondary.opacity(0.55)
        }
    }
}

private struct RemoteControlView: View {
    @ObservedObject var model: EarControlModel

    var body: some View {
        VStack(spacing: 11) {
            ForEach(HardwareControl.allCases) { control in
                ZStack {
                    RoundedRectangle(cornerRadius: control == .middle ? 20 : 12, style: .continuous)
                        .fill(model.isActive(control) ? Color.accentColor : Color(red: 0.30, green: 0.31, blue: 0.33))
                    RoundedRectangle(cornerRadius: control == .middle ? 20 : 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(model.isActive(control) ? 0.42 : 0.17), lineWidth: 0.75)
                    RemoteButtonSymbol(control: control)
                        .foregroundColor(.white.opacity(model.isActive(control) ? 1 : 0.9))
                }
                .frame(width: 48, height: 48)
                .accessibilityLabel(control.diagnosticTitle)
                .accessibilityValue(model.isActive(control) ? "正在执行" : "未按下")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 13)
        .background(
            LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
        .allowsHitTesting(false)
    }
}

private struct RemoteButtonSymbol: View {
    let control: HardwareControl

    var body: some View {
        switch control {
        case .volumeUp:
            ZStack {
                Capsule().frame(width: 16, height: 2.2)
                Capsule().frame(width: 2.2, height: 16)
            }
        case .middle:
            Circle().frame(width: 9, height: 9)
        case .volumeDown:
            Capsule().frame(width: 16, height: 2.2)
        }
    }
}

private struct MappingDescription: View {
    let title: String
    let detail: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(height: 59, alignment: .leading)
    }
}

private struct MiddleGestureSummary: View {
    let mappings: MiddleGestureMappings
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("中键手势")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.primary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(MiddleGesture.allCases) { gesture in
                    gestureItem(gesture)
                }
            }
        }
        .frame(height: 83, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("中键手势")
        .accessibilityValue(mappings.compactSummary)
    }

    private func gestureItem(_ gesture: MiddleGesture) -> some View {
        let action = mappings[gesture]
        return HStack(spacing: 7) {
            Text(gesture.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 25, alignment: .leading)

            HStack(spacing: 3) {
                Image(systemName: actionIcon(action))
                    .font(.system(size: 8, weight: .medium))
                    .frame(width: 11)
                Text(actionTitle(action))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(active ? Color.accentColor : (action == nil ? Color.secondary : Color.primary))
        }
        .frame(height: 15)
    }

    private func actionTitle(_ action: MiddleGestureAction?) -> String {
        guard let action else { return "结束语音" }
        return switch action.kind {
        case .shortcut: action.recordedShortcut?.displayTitle ?? "快捷键"
        case .selectAllAndDelete: "清空"
        case .finishVoiceAndSend: "整理并发送"
        }
    }

    private func actionIcon(_ action: MiddleGestureAction?) -> String {
        guard let action else { return "mic.slash" }
        return switch action.kind {
        case .shortcut: "keyboard"
        case .selectAllAndDelete: "delete.left"
        case .finishVoiceAndSend: "paperplane"
        }
    }
}

struct EarControlSettings: View {
    @ObservedObject var model: EarControlModel
    @State private var selectedSection = SettingsSection.general

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button {
                        model.onReturnToPanel?()
                    } label: {
                        Label("返回菜单栏", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("关闭设置并重新显示 EarControl 菜单栏面板")

                    Spacer()
                }

                Picker("设置页面", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
            }
            .frame(height: 32)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Divider()

            Group {
                switch selectedSection {
                case .general:
                    GeneralSettings(model: model)
                case .diagnostics:
                    DiagnosticsSettings(model: model)
                case .about:
                    AboutSettings(model: model)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .diagnostics: "按键诊断"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .diagnostics: "list.bullet.rectangle"
        case .about: "info.circle"
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: EarControlModel

    var body: some View {
        Form {
            Section("语音工作流") {
                Picker("语音触发键", selection: Binding(
                    get: { model.voiceModifier },
                    set: { model.onSelectModifier?($0) }
                )) {
                    ForEach(VoiceModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                Text("微信输入法中的“按住说话”快捷键必须与这里一致。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("恢复默认三键映射") { model.onResetMappings?() }
            }

            Section("中键手势") {
                ForEach(MiddleGesture.allCases) { gesture in
                    ShortcutRecorderRow(
                        gesture: gesture,
                        action: model.middleGestureMappings[gesture],
                        onChange: { model.onSetMiddleGestureAction?(gesture, $0) }
                    )
                }
                Text("任意中键手势都会先结束当前语音。单击等待 0.35 秒以区分连击；长按仍保持全选并清空。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("登录时自动启动 EarControl", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { _ in model.onToggleLaunchAtLogin?() }
                ))
            }

            Section("权限") {
                LabeledContent("辅助功能") {
                    Text(model.accessibilityTrusted ? "已授权" : "未授权，映射不会执行")
                        .foregroundStyle(model.accessibilityTrusted ? Color.green : Color.orange)
                }
                LabeledContent("键盘事件发送") {
                    Text(model.eventPostingTrusted ? "已允许" : "未允许")
                        .foregroundStyle(model.eventPostingTrusted ? Color.green : Color.orange)
                }
                LabeledContent("输入监控") {
                    Text(model.inputMonitoringTrusted ? "已允许" : (model.inputMonitoringRequired ? "当前需要" : "当前可选"))
                        .foregroundStyle(model.inputMonitoringTrusted ? Color.green : (model.inputMonitoringRequired ? Color.orange : Color.secondary))
                }
                HStack {
                    Button("运行设置检查…") { model.onOpenSetup?() }
                    Button("微信输入法设置…") { model.onOpenWeType?() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiagnosticsSettings: View {
    @ObservedObject var model: EarControlModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("运行状态") {
                    VStack(spacing: 8) {
                        DiagnosticLine(label: "连接", value: model.connectionState.diagnosticTitle)
                        DiagnosticLine(label: "辅助功能", value: model.accessibilityTrusted ? "已授权" : "未授权")
                        DiagnosticLine(label: "键盘发送", value: model.eventPostingTrusted ? "已允许" : "未允许")
                        DiagnosticLine(label: "输入监控", value: model.inputMonitoringTrusted ? "已允许" : (model.inputMonitoringRequired ? "当前需要" : "当前可选"))
                        DiagnosticLine(label: "当前输入", value: model.microphoneName)
                        DiagnosticLine(label: "最近映射", value: model.lastMappedAction)
                        DiagnosticLine(label: "原始报告", value: "\(model.rawEventCount) 条")
                        DiagnosticLine(label: "三键检测", value: "\(model.testedControlCount)/3")
                        DiagnosticLine(label: "中键映射", value: model.middleGestureMappings.compactSummary)
                        DiagnosticLine(label: "工作流", value: model.workflowVerified ? "已通过" : "未完成")
                    }
                    .padding(6)
                }

                GroupBox("最近 HID 事件") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            if model.recentEvents.isEmpty {
                                Text("按下任意线控键后，原始事件会显示在这里。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(model.recentEvents) { event in
                                    Text(event.description)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .frame(minHeight: 96, idealHeight: 120, maxHeight: 150)
                }

                HStack {
                    Button("复制诊断信息") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.diagnosticsText, forType: .string)
                    }
                    Button("清除记录") { model.onClearDiagnostics?() }
                    Spacer()
                }
            }
            .padding(4)
        }
    }
}

private struct AboutSettings: View {
    @ObservedObject var model: EarControlModel

    var body: some View {
        VStack(spacing: 14) {
            RemoteBrandMark()
                .frame(width: 74, height: 74)
            Text("EarControl")
                .font(.system(size: 22, weight: .semibold))
            Text("v\(model.version)")
                .foregroundStyle(.secondary)
            Text("把 Apple 有线 EarPods 的三枚线控键变成语音输入工作流。音频由系统与输入法处理，EarControl 不录音，也不上传音频。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 390)
            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/HeJianBTW/EarControl")!)
                Link("MIT License", destination: URL(string: "https://github.com/HeJianBTW/EarControl/blob/main/LICENSE")!)
            }
            .font(.system(size: 12))
            Text("独立实现，与 Apple、微信输入法无隶属关系。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiagnosticLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(size: 11))
    }
}

struct RemoteBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.23), Color(white: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Capsule()
                .stroke(Color.white.opacity(0.88), lineWidth: 3)
                .frame(width: 20, height: 48)
            VStack(spacing: 7) {
                Circle().fill(Color.white).frame(width: 5, height: 5)
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                Circle().fill(Color.white).frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("EarControl 三键线控标志")
    }
}

func makeMenuBarRemoteImage(color: NSColor) -> NSImage {
    let pointSize = NSSize(width: 18, height: 18)
    let scale: CGFloat = 2
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pointSize.width * scale),
        pixelsHigh: Int(pointSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return NSImage(size: pointSize)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    autoreleasepool {
        let resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        resolvedColor.setStroke()
        resolvedColor.setFill()

        let cable = NSBezierPath()
        cable.lineWidth = 1.35
        cable.lineCapStyle = .round
        cable.move(to: NSPoint(x: 9, y: 16.8))
        cable.line(to: NSPoint(x: 9, y: 15.2))
        cable.move(to: NSPoint(x: 9, y: 2.8))
        cable.line(to: NSPoint(x: 9, y: 1.2))
        cable.stroke()

        let body = NSBezierPath(roundedRect: NSRect(x: 5.25, y: 2.75, width: 7.5, height: 12.5), xRadius: 3.2, yRadius: 3.2)
        body.lineWidth = 1.35
        body.stroke()

        for y in [12.1, 9.0, 5.9] {
            NSBezierPath(ovalIn: NSRect(x: 8.0, y: y - 1, width: 2, height: 2)).fill()
        }
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    bitmap.size = pointSize
    let image = NSImage(size: pointSize)
    image.addRepresentation(bitmap)
    // Thaw/Ice captures status item window pixels and does not preserve the
    // template flag, so provide already-resolved monochrome pixels instead.
    image.isTemplate = false
    return image
}
