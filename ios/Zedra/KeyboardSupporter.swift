import UIKit

@_silgen_name("zedra_ios_set_ctrl_state")
private func zedra_ios_set_ctrl_state(_ state: UInt8)

@_silgen_name("zedra_ios_get_ctrl_state")
private func zedra_ios_get_ctrl_state() -> UInt8

@objcMembers
final class KeyboardSupporter: NSObject {
    private struct KeySpec {
        let label: String
        let key: String
        let repeats: Bool
        let isModifier: Bool
    }

    private let keySpecs = [
        KeySpec(label: "Ctrl", key: "ctrl", repeats: false, isModifier: true),
        KeySpec(label: "Esc", key: "escape", repeats: false, isModifier: false),
        KeySpec(label: "Tab", key: "tab", repeats: false, isModifier: false),
        KeySpec(label: "←", key: "left", repeats: true, isModifier: false),
        KeySpec(label: "↓", key: "down", repeats: true, isModifier: false),
        KeySpec(label: "↑", key: "up", repeats: true, isModifier: false),
        KeySpec(label: "→", key: "right", repeats: true, isModifier: false),
        KeySpec(label: "⏎", key: "enter", repeats: false, isModifier: false),
    ]

    private let repeatInitialDelay: TimeInterval = 0.35
    private let repeatInterval: TimeInterval = 0.06
    private let modifierTimeout: TimeInterval = 2.0

    private(set) var accessoryView: UIView?
    private var sendKey: ((String) -> Void)?
    private var repeatTimer: Timer?
    private var repeatingKey: String?

    private var ctrlActive = false
    private var ctrlLocked = false
    private var deactivationTimer: Timer?
    private var ctrlButton: UIButton?

    func makeAccessoryView(width: CGFloat, sendKey: @escaping (String) -> Void) -> UIView {
        stopRepeating()
        deactivateCtrl()
        self.sendKey = sendKey

        let height: CGFloat = 44.0
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        bar.backgroundColor = UIColor(red: 0.055, green: 0.047, blue: 0.047, alpha: 0.96)
        if #available(iOS 13.0, *) {
            bar.overrideUserInterfaceStyle = .dark
        }

        let border = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 0.33))
        border.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        bar.addSubview(border)

        let buttonWidth = width / CGFloat(keySpecs.count)

        for (index, spec) in keySpecs.enumerated() {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: buttonWidth * CGFloat(index), y: 0, width: buttonWidth, height: height)
            button.setTitle(spec.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16.0)
            let color = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
            button.setTitleColor(color, for: .normal)
            button.tintColor = color
            if #available(iOS 13.0, *) {
                button.overrideUserInterfaceStyle = .dark
            }
            button.tag = index
            button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(buttonTouchUpInside(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(stopRepeating), for: .touchUpOutside)
            button.addTarget(self, action: #selector(stopRepeating), for: .touchCancel)
            button.addTarget(self, action: #selector(stopRepeating), for: .touchDragExit)
            bar.addSubview(button)
            if spec.isModifier {
                ctrlButton = button
            }
        }

        accessoryView = bar
        return bar
    }

    @objc func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatingKey = nil
        if ctrlActive && !ctrlLocked {
            deactivateCtrl()
        }
    }

    private func keySpec(for sender: UIButton) -> KeySpec? {
        guard keySpecs.indices.contains(sender.tag) else {
            return nil
        }
        return keySpecs[sender.tag]
    }

    @objc
    private func buttonTouchDown(_ sender: UIButton) {
        guard let spec = keySpec(for: sender) else { return }

        if spec.isModifier {
            handleModifierTap()
            return
        }

        let keyToSend = compoundKey(spec.key)
        if spec.repeats {
            sendKey?(keyToSend)
            startRepeating(keyToSend)
        }
    }

    @objc
    private func buttonTouchUpInside(_ sender: UIButton) {
        guard let spec = keySpec(for: sender) else {
            stopRepeating()
            return
        }
        if spec.isModifier { return }

        if spec.repeats {
            stopRepeating()
        } else {
            sendKey?(compoundKey(spec.key))
            if ctrlActive && !ctrlLocked {
                deactivateCtrl()
            }
        }
    }

    // MARK: - Ctrl modifier state

    private func handleModifierTap() {
        cancelDeactivationTimer()
        if ctrlLocked {
            deactivateCtrl()
        } else if ctrlActive {
            ctrlLocked = true
            ctrlActive = false
            syncCtrlStateToRust()
            updateCtrlHighlight()
        } else {
            ctrlActive = true
            syncCtrlStateToRust()
            updateCtrlHighlight()
            startDeactivationTimer()
        }
    }

    private func deactivateCtrl() {
        ctrlActive = false
        ctrlLocked = false
        cancelDeactivationTimer()
        syncCtrlStateToRust()
        updateCtrlHighlight()
    }

    private func updateCtrlHighlight() {
        let active = ctrlActive || ctrlLocked
        ctrlButton?.backgroundColor = active
            ? UIColor.systemBlue.withAlphaComponent(0.3)
            : .clear
    }

    // Polls at 150ms while one-shot is active to detect when Rust consumes
    // the one-shot via native keyboard input. Also enforces the 2s timeout.
    private func startDeactivationTimer() {
        cancelDeactivationTimer()
        let startTime = Date()
        deactivationTimer = Timer.scheduledTimer(
            withTimeInterval: 0.15,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            // Rust consumed the one-shot via native keyboard letter
            if !self.ctrlLocked && zedra_ios_get_ctrl_state() == 0 {
                self.deactivateCtrl()
                return
            }
            // 2s timeout
            if Date().timeIntervalSince(startTime) >= self.modifierTimeout {
                self.deactivateCtrl()
            }
        }
    }

    private func cancelDeactivationTimer() {
        deactivationTimer?.invalidate()
        deactivationTimer = nil
    }

    private func syncCtrlStateToRust() {
        let state: UInt8
        if ctrlLocked {
            state = 2
        } else if ctrlActive {
            state = 1
        } else {
            state = 0
        }
        zedra_ios_set_ctrl_state(state)
    }

    private func compoundKey(_ key: String) -> String {
        (ctrlActive || ctrlLocked) ? "ctrl+\(key)" : key
    }

    private func startRepeating(_ key: String) {
        stopRepeating()
        repeatingKey = key

        let timer = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
            guard let self, self.repeatingKey == key else { return }
            self.sendKey?(key)
        }
        timer.fireDate = Date(timeIntervalSinceNow: repeatInitialDelay)
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
