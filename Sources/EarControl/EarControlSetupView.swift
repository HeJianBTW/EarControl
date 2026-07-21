import SwiftUI

struct EarControlSetupView: View {
    @ObservedObject var model: EarControlModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    headsetSection
                    permissionSection
                    microphoneSection
                    verificationSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            footer
        }
        .frame(width: 620, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            RemoteBrandMark()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("设置 EarControl")
                    .font(.system(size: 22, weight: .semibold))
                Text("逐项确认线控、权限与麦克风，避免出现只有界面响应却没有实际操作。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SetupStatusBadge(ready: model.setupReady)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var headsetSection: some View {
        SetupGroup(title: "1  连接线控", systemImage: "cable.connector") {
            SetupCheckRow(
                title: "Apple 有线耳机",
                detail: model.connectionState.diagnosticTitle,
                state: model.connectionState.isConnected ? .passed : (model.connectionState == .starting ? .checking : .attention)
            )
            if model.connectionState == .connectedFallback {
                Text("当前使用事件过滤回退，需要输入监控权限才能可靠阻止原始音量与播放动作。")
                    .setupNote()
            } else if model.connectionState == .disconnected {
                Text("请将 EarPods 插入 Mac；连接后本页会自动更新。")
                    .setupNote()
            }
        }
    }

    private var permissionSection: some View {
        SetupGroup(title: "2  系统权限", systemImage: "checkmark.shield") {
            SetupCheckRow(
                title: "辅助功能身份",
                detail: model.accessibilityTrusted ? "当前应用已获得授权" : "尚未授权",
                state: model.accessibilityTrusted ? .passed : .attention,
                buttonTitle: model.accessibilityTrusted ? nil : "打开设置…",
                action: model.onRequestAccessibility
            )
            SetupCheckRow(
                title: "键盘事件发送",
                detail: eventPostingDetail,
                state: model.eventPostingTrusted ? .passed : .attention,
                buttonTitle: model.eventPostingTrusted ? nil : "修复授权…",
                action: model.onRequestAccessibility
            )
            if model.accessibilityTrusted && !model.eventPostingTrusted {
                Text("辅助功能开关虽然已打开，但发送授权尚未进入当前进程。请先完全退出并重新打开 EarControl；如果仍未生效，再在系统设置中删除旧 EarControl，并重新添加 /Applications/EarControl.app。")
                    .setupNote()
            }
            SetupCheckRow(
                title: "输入监控",
                detail: inputMonitoringDetail,
                state: inputMonitoringState,
                buttonTitle: inputMonitoringButtonTitle,
                action: model.onRequestInputMonitoring
            )
        }
    }

    private var microphoneSection: some View {
        SetupGroup(title: "3  输入设备", systemImage: "mic") {
            SetupCheckRow(
                title: model.microphoneName,
                detail: model.defaultInputIsWired ? "当前默认输入是有线麦克风" : "当前默认输入不是有线耳机麦克风",
                state: model.defaultInputIsWired ? .passed : .optional
            )
            if !model.defaultInputIsWired {
                Text("EarControl 不录音，也不会强制切换系统输入。若希望使用耳麦，请在“系统设置 → 声音 → 输入”中选择 External Microphone。")
                    .setupNote()
            }
        }
    }

    private var verificationSection: some View {
        SetupGroup(title: "4  按键与工作流验证", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("三枚物理按键识别（只验证硬件信号）")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(model.testedControlCount)/3")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.testedControlCount == 3 ? Color.green : Color.secondary)
                }
                HStack(spacing: 8) {
                    ControlTestChip(title: "音量加", passed: model.seenControls.contains(.volumeUp))
                    ControlTestChip(title: "中间键", passed: model.seenControls.contains(.middle))
                    ControlTestChip(title: "音量减", passed: model.seenControls.contains(.volumeDown))
                }
            }
            SetupCheckRow(
                title: "语音工作流",
                detail: model.workflowVerified ? "开始、结束与发送均已执行" : "用线控完成一次“开始说话 → 结束 → 发送”",
                state: model.workflowVerified ? .passed : .optional
            )
        }
    }

    private var footer: some View {
        HStack {
            Label("所有检查都在本机完成，不读取或上传音频", systemImage: "lock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("稍后") { model.onDismissSetup?() }
                .keyboardShortcut(.cancelAction)
            Button("完成设置") { model.onCompleteSetup?() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.setupReady)
                .help(model.setupReady ? "保存设置并关闭向导" : "连接耳机并完成当前连接模式所需权限后即可完成")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var inputMonitoringDetail: String {
        if model.inputMonitoringTrusted { return "已允许读取回退事件" }
        return model.inputMonitoringRequired ? "当前连接模式需要此权限" : "HID 独占模式下暂不需要"
    }

    private var eventPostingDetail: String {
        if model.eventPostingTrusted { return "可以发送右 Option、Return 等事件" }
        return model.accessibilityTrusted ? "开关已打开，但发送授权尚未生效" : "系统会拦截映射动作"
    }

    private var inputMonitoringState: SetupCheckState {
        if model.inputMonitoringTrusted { return .passed }
        return model.inputMonitoringRequired ? .attention : .optional
    }

    private var inputMonitoringButtonTitle: String? {
        guard !model.inputMonitoringTrusted else { return nil }
        return model.inputMonitoringRequired ? "打开设置…" : "按需授权…"
    }
}

private enum SetupCheckState {
    case checking
    case passed
    case attention
    case optional

    var color: Color {
        switch self {
        case .checking: .blue
        case .passed: .green
        case .attention: .orange
        case .optional: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .checking: "ellipsis"
        case .passed: "checkmark"
        case .attention: "exclamationmark"
        case .optional: "minus"
        }
    }
}

private struct SetupGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(spacing: 12) { content }
                .padding(4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct SetupCheckRow: View {
    let title: String
    let detail: String
    let state: SetupCheckState
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(state.color.opacity(0.14))
                Image(systemName: state.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(state.color)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let buttonTitle {
                Button(buttonTitle) { action?() }
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ControlTestChip: View {
    let title: String
    let passed: Bool

    var body: some View {
        Label(title, systemImage: passed ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(passed ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct SetupStatusBadge: View {
    let ready: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ready ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(ready ? "基础链路正常" : "等待完成")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func setupNote() -> some View {
        self
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 35)
    }
}
