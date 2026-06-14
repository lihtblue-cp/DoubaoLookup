import Cocoa
import WebKit
import Carbon

// MARK: - 通知

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("com.doubaolookup.hotkeyDidChange")
}

// MARK: - 快捷键录制控件

class HotkeyRecorderView: NSView {

    var currentKeyCode: UInt32 = 0
    var currentModifiers: UInt32 = 0
    var isRecording = false
    var onChange: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private let textField: NSTextField

    // 常用键位映射
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "5",
        23: "6", 24: "7", 25: "8", 26: "9", 27: "0",
        28: "-", 29: "=", 30: "⌫", 31: "⇥", 32: "Y", 33: "U", 34: "I",
        35: "O", 36: "P", 37: "[", 38: "]", 39: "\\",
        41: ";", 42: "'", 43: "`", 44: ",", 45: ".", 46: "/",
        47: "⇪", 48: "⎋", 49: "Space",
        50: "⌂", 51: "⌦", 53: "⎋",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    init(frame: NSRect, keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers

        textField = NSTextField(labelWithString: "")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        textField.alignment = .center
        textField.frame = frame.insetBy(dx: 8, dy: 4)
        textField.autoresizingMask = [.width, .height]

        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        addSubview(textField)
        updateDisplay()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: 绘制

    func updateDisplay() {
        if isRecording {
            textField.stringValue = "按下快捷键..."
            textField.textColor = .controlAccentColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else {
            textField.stringValue = displayString
            textField.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    private var displayString: String {
        var parts = [String]()
        let mods = currentModifiers
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(optionKey) != 0  { parts.append("⌥") }
        if mods & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if mods & UInt32(cmdKey) != 0     { parts.append("⌘") }
        let name = Self.keyNames[UInt16(truncatingIfNeeded: currentKeyCode)] ?? "KEY-\(currentKeyCode)"
        parts.append(name)
        return parts.joined()
    }

    // MARK: 事件处理

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        updateDisplay()
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        updateDisplay()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateDisplay()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let keyCode = UInt32(event.keyCode)

        // Esc → 取消
        if event.keyCode == 53 {
            isRecording = false
            updateDisplay()
            window?.makeFirstResponder(nil)
            return
        }

        // 需要至少一个修饰键
        let mods = carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else { return }

        currentKeyCode = keyCode
        currentModifiers = mods
        isRecording = false

        window?.makeFirstResponder(nil)
        updateDisplay()
        onChange?(currentKeyCode, currentModifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        // 单独修饰键变化时不做处理，等待 keyDown
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}

// MARK: - 设置窗口

class SettingsWindowController: NSWindowController {

    private weak var floatingWC: FloatingWebWindowController?
    private var hotkeyRecorder: HotkeyRecorderView!
    private var statusLabel: NSTextField!
    private var statusSpinner: NSProgressIndicator!
    private var hintLabel: NSTextField!

    // MARK: 初始化

    init(floatingWC: FloatingWebWindowController) {
        self.floatingWC = floatingWC
        let window = Self.createWindow()
        super.init(window: window)
        setupUI()
    }

    override init(window: NSWindow?) {
        self.floatingWC = nil
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func createWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "设置"
        win.isReleasedWhenClosed = false
        win.level = .floating
        return win
    }

    // MARK: 界面

    private func setupUI() {
        guard let v = window?.contentView else { return }

        // ── 标题 ──
        let title = NSTextField(labelWithString: "豆包查询")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 20, y: v.bounds.height - 38, width: 200, height: 22)
        v.addSubview(title)

        // ── 快捷键 ──
        let hotkeySection = sectionLabel(frame: NSRect(x: 20, y: v.bounds.height - 65, width: 200, height: 18), text: "快捷键")
        v.addSubview(hotkeySection)

        let savedKeyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let savedMods = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))

        hotkeyRecorder = HotkeyRecorderView(
            frame: NSRect(x: 20, y: v.bounds.height - 100, width: 160, height: 32),
            keyCode: savedKeyCode,
            modifiers: savedMods
        )
        hotkeyRecorder.onChange = { [weak self] keyCode, modifiers in
            guard let self = self else { return }

            let conflicts = Self.findSystemConflicts(keyCode: keyCode, modifiers: modifiers)
            if !conflicts.isEmpty {
                let alert = NSAlert()
                alert.messageText = "快捷键冲突"
                alert.informativeText = "「\(conflicts.joined(separator: "、"))」已被系统或其他应用占用，继续使用可能导致该快捷键在部分应用中失效。\n\n确定要覆盖使用该快捷键吗？"
                alert.addButton(withTitle: "仍然使用")
                alert.addButton(withTitle: "重新选择")
                alert.beginSheetModal(for: self.window!) { response in
                    if response == .alertFirstButtonReturn {
                        self.saveHotkey(keyCode: keyCode, modifiers: modifiers)
                        self.hotkeySavedFeedback(keyCode: keyCode, modifiers: modifiers)
                    } else {
                        // 恢复为之前保存的值，并重新进入录制状态
                        let savedKC = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
                        let savedMods = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
                        self.hotkeyRecorder.currentKeyCode = savedKC
                        self.hotkeyRecorder.currentModifiers = savedMods
                        self.hotkeyRecorder.isRecording = true
                        self.hotkeyRecorder.updateDisplay()
                        self.hotkeyRecorder.window?.makeFirstResponder(self.hotkeyRecorder)
                    }
                }
                return
            }

            self.saveHotkey(keyCode: keyCode, modifiers: modifiers)
            self.hotkeySavedFeedback(keyCode: keyCode, modifiers: modifiers)
        }
        v.addSubview(hotkeyRecorder)

        hintLabel = NSTextField(labelWithString: "点击上方区域后按下新快捷键")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 20, y: v.bounds.height - 120, width: 280, height: 16)
        hintLabel.autoresizingMask = [.width]
        v.addSubview(hintLabel)

        // ── 分隔线 ──
        let sep = NSBox(frame: NSRect(x: 20, y: v.bounds.height - 145, width: v.bounds.width - 40, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width]
        v.addSubview(sep)

        // ── 豆包账户 ──
        let acctSection = sectionLabel(frame: NSRect(x: 20, y: v.bounds.height - 172, width: 200, height: 18), text: "豆包账户")
        v.addSubview(acctSection)

        statusLabel = NSTextField(labelWithString: "登录状态: 检测中...")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 20, y: v.bounds.height - 195, width: 250, height: 18)
        v.addSubview(statusLabel)

        // 按钮
        let loginBtn = NSButton(title: "打开登录页", target: self, action: #selector(loginTapped))
        loginBtn.bezelStyle = .rounded
        loginBtn.frame = NSRect(x: 20, y: v.bounds.height - 232, width: 110, height: 26)
        v.addSubview(loginBtn)

        let logoutBtn = NSButton(title: "退出登录", target: self, action: #selector(logoutTapped))
        logoutBtn.bezelStyle = .rounded
        logoutBtn.frame = NSRect(x: 140, y: v.bounds.height - 232, width: 110, height: 26)
        v.addSubview(logoutBtn)

        // 加载状态指示
        statusSpinner = NSProgressIndicator(frame: NSRect(x: 172, y: v.bounds.height - 195, width: 16, height: 16))
        statusSpinner.style = .spinning
        statusSpinner.controlSize = .small
        statusSpinner.isDisplayedWhenStopped = false
        v.addSubview(statusSpinner)
    }

    private func sectionLabel(frame: NSRect, text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        lbl.frame = frame
        return lbl
    }

    // MARK: 窗口生命周期

    override func showWindow(_ sender: Any?) {
        // 居中于鼠标所在屏幕
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let winSize = window?.frame.size ?? NSSize(width: 380, height: 270)
            let x = screen.visibleFrame.midX - winSize.width / 2
            let y = screen.visibleFrame.midY - winSize.height / 2
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        super.showWindow(sender)
        window?.makeKey()
        checkLoginStatus()
    }

    // MARK: 快捷键存储

    /// 通用的 macOS 菜单快捷键（各应用通用，CopySymbolicHotKeys 不包含这些）
    private static let commonAppShortcuts: [(keyCode: UInt32, modifiers: UInt32, name: String)] = [
        (8,  UInt32(cmdKey), "⌘C — 复制"),
        (9,  UInt32(cmdKey), "⌘V — 粘贴"),
        (7,  UInt32(cmdKey), "⌘X — 剪切"),
        (6,  UInt32(cmdKey), "⌘Z — 撤销"),
        (0,  UInt32(cmdKey), "⌘A — 全选"),
        (1,  UInt32(cmdKey), "⌘S — 保存"),
        (3,  UInt32(cmdKey), "⌘F — 查找"),
        (36, UInt32(cmdKey), "⌘P — 打印"),
        (13, UInt32(cmdKey), "⌘W — 关闭窗口"),
        (12, UInt32(cmdKey), "⌘Q — 退出"),
        (46, UInt32(cmdKey), "⌘/ — 帮助"),
        (4,  UInt32(cmdKey), "⌘H — 隐藏"),
        (5,  UInt32(cmdKey), "⌘G — 查找下一个"),
        (2,  UInt32(cmdKey), "⌘D — 复制/收藏"),
        (14, UInt32(cmdKey), "⌘E — 使用选择查找"),
        (17, UInt32(cmdKey), "⌘T — 新建标签页"),
        (15, UInt32(cmdKey), "⌘R — 刷新"),
        (31, UInt32(cmdKey), "⌘⇥ — 切换应用"),
        (37, UInt32(cmdKey), "⌘[ — 后退"),
        (38, UInt32(cmdKey), "⌘] — 前进"),
        (6,  UInt32(cmdKey) | UInt32(shiftKey), "⌘⇧Z — 重做"),
        (45, UInt32(cmdKey), "⌘. — 取消"),
        (49, UInt32(cmdKey), "⌘Space — 聚焦搜索"),
        (49, UInt32(controlKey) | UInt32(cmdKey), "⌃⌘Space — 字符检视器"),
        (20, UInt32(shiftKey) | UInt32(cmdKey), "⌘⇧3 — 截取全屏"),
        (21, UInt32(shiftKey) | UInt32(cmdKey), "⌘⇧4 — 截取所选区域"),
        (22, UInt32(shiftKey) | UInt32(cmdKey), "⌘⇧5 — 截屏工具"),
        (53, UInt32(optionKey) | UInt32(cmdKey), "⌥⌘⎋ — 强制退出"),
        (12, UInt32(controlKey) | UInt32(cmdKey), "⌃⌘Q — 锁定屏幕"),
    ]

    /// 检测快捷键是否与系统中已注册的快捷键或通用菜单快捷键冲突
    /// 返回所有冲突的描述列表
    private static func findSystemConflicts(keyCode: UInt32, modifiers: UInt32) -> [String] {
        var conflicts: [String] = []

        // 1. 检查通用应用快捷键（⌘C、⌘V 等）
        for shortcut in commonAppShortcuts {
            if shortcut.keyCode == keyCode && shortcut.modifiers == modifiers {
                conflicts.append(shortcut.name)
            }
        }

        // 2. 检查系统全局快捷键（CopySymbolicHotKeys）
        var hotKeysRef: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeysRef) == noErr,
              let hotKeys = hotKeysRef?.takeRetainedValue() as? [CFDictionary] else {
            return conflicts
        }
        for dict in hotKeys {
            let nsDict = dict as NSDictionary
            guard let kcNum = nsDict[kHISymbolicHotKeyCode] as? NSNumber,
                  let modNum = nsDict[kHISymbolicHotKeyModifiers] as? NSNumber,
                  let enabled = nsDict[kHISymbolicHotKeyEnabled] as? NSNumber,
                  enabled.boolValue
            else { continue }
            if kcNum.uint32Value == keyCode && modNum.uint32Value == modifiers {
                let name = keyName(for: UInt16(truncatingIfNeeded: keyCode)) ?? "KEY-\(keyCode)"
                let modStr = hotkeyModifierString(modifiers)
                let desc = "\(modStr)\(name)"
                if !conflicts.contains(desc) {
                    conflicts.append(desc)
                }
            }
        }
        return conflicts
    }

    private static func hotkeyModifierString(_ modifiers: UInt32) -> String {
        var parts = [String]()
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0  { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0     { parts.append("⌘") }
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "5",
            23: "6", 24: "7", 25: "8", 26: "9", 27: "0",
            28: "-", 29: "=", 30: "⌫", 31: "⇥",
            33: "U", 34: "I", 35: "O", 36: "P", 37: "[", 38: "]", 39: "\\",
            41: ";", 42: "'", 43: "`", 44: ",", 45: ".", 46: "/",
            47: "⇪", 48: "⎋", 49: "Space",
            51: "⌦", 53: "⎋",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode]
    }

    /// 快捷键保存成功后的反馈：更新录制器显示 + 提示
    private func hotkeySavedFeedback(keyCode: UInt32, modifiers: UInt32) {
        // 强制设置录制器的显示值并退出录制状态
        hotkeyRecorder.currentKeyCode = keyCode
        hotkeyRecorder.currentModifiers = modifiers
        hotkeyRecorder.isRecording = false
        hotkeyRecorder.updateDisplay()
        hotkeyRecorder.window?.makeFirstResponder(nil)

        // 显示「✓ 设置成功」反馈
        let origText = hintLabel.stringValue
        let origColor = hintLabel.textColor
        hintLabel.stringValue = "✓ 设置成功"
        hintLabel.textColor = NSColor.systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.hintLabel.stringValue = origText
            self.hintLabel.textColor = origColor
        }
    }

    private func saveHotkey(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyModifiers")
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    // MARK: 账户

    private func checkLoginStatus() {
        statusSpinner?.startAnimation(nil)
        statusLabel.stringValue = "登录状态: 检测中..."

        guard let webView = floatingWC?.webViewForCookieStore else {
            statusLabel.stringValue = "登录状态: 未知"
            statusSpinner?.stopAnimation(nil)
            return
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let hasSession = cookies.contains { cookie in
                    cookie.domain.contains("doubao.com") &&
                    (cookie.name.localizedCaseInsensitiveContains("session") ||
                     cookie.name.localizedCaseInsensitiveContains("token") ||
                     cookie.name.localizedCaseInsensitiveContains("sso") ||
                     cookie.name.localizedCaseInsensitiveContains("auth"))
                }
                self.statusLabel.stringValue = hasSession ? "登录状态: 已登录" : "登录状态: 未登录"
                self.statusSpinner?.stopAnimation(nil)
            }
        }
    }

    @objc private func loginTapped() {
        floatingWC?.navigateToLogin()
        close()
    }

    @objc private func logoutTapped() {
        statusLabel.stringValue = "正在退出登录..."
        statusSpinner?.startAnimation(nil)
        floatingWC?.clearCookies { [weak self] in
            DispatchQueue.main.async {
                self?.checkLoginStatus()
            }
        }
    }
}
