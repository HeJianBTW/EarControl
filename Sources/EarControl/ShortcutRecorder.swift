import AppKit
import SwiftUI

struct ShortcutRecorderRow: View {
    let gesture: MiddleGesture
    let action: MiddleGestureAction?
    let onChange: (MiddleGestureAction?) -> Void

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture.title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 118, alignment: .leading)

            Group {
                if isRecording {
                    selectionLabel(recording: true)
                        .background {
                            ShortcutCaptureView(
                                onCapture: { captured in
                                    onChange(.shortcut(captured))
                                    isRecording = false
                                },
                                onCancel: { isRecording = false }
                            )
                            .frame(width: 1, height: 1)
                        }
                } else {
                    Menu {
                        Button("录制快捷键…") { isRecording = true }
                        Divider()
                        Button("全选并删除") { onChange(.selectAllAndDelete) }
                        Button("结束语音并发送") { onChange(.finishVoiceAndSend) }
                    } label: {
                        selectionLabel(recording: false)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("中键\(gesture.title)动作")
            .accessibilityValue(action?.displayTitle ?? "未设置")

            Button {
                onChange(nil)
                isRecording = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(action == nil ? Color.secondary.opacity(0.35) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(action == nil)
            .help("清除\(gesture.title)映射")
        }
    }

    private func selectionLabel(recording: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: recording ? "keyboard.fill" : "keyboard")
            Text(recording ? "请按快捷键…" : (action?.displayTitle ?? "未设置"))
                .lineLimit(1)
            Spacer(minLength: 6)
            if !recording {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: recording ? .semibold : .medium))
        .foregroundStyle(recording ? Color.accentColor : Color.primary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            recording ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var detail: String {
        switch gesture {
        case .single: "默认只结束语音"
        case .double, .triple: "默认不执行额外按键"
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (RecordedShortcut) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { [weak nsView] in
                nsView?.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator {
        var onCapture: (RecordedShortcut) -> Void
        var onCancel: () -> Void

        init(onCapture: @escaping (RecordedShortcut) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    weak var coordinator: ShortcutCaptureView.Coordinator?
    private var modifierCandidate: UInt16?
    private var sawMultipleModifiers = false
    private var completed = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !completed, !event.isARepeat else { return }
        completed = true
        coordinator?.onCapture(.key(
            keyCode: event.keyCode,
            modifiers: RecordedShortcut.normalized(event.modifierFlags)
        ))
    }

    override func flagsChanged(with event: NSEvent) {
        guard !completed,
              RecordedShortcut.isSupportedModifierKeyCode(event.keyCode),
              let flag = RecordedShortcut.modifierFlag(for: event.keyCode)
        else { return }

        if event.modifierFlags.contains(flag) {
            if let modifierCandidate, modifierCandidate != event.keyCode {
                sawMultipleModifiers = true
            } else if modifierCandidate == nil {
                modifierCandidate = event.keyCode
            }
            return
        }

        guard modifierCandidate == event.keyCode, !sawMultipleModifiers,
              let shortcut = RecordedShortcut.modifier(keyCode: event.keyCode)
        else { return }
        completed = true
        coordinator?.onCapture(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, !completed {
            coordinator?.onCancel()
        }
        return result
    }
}
