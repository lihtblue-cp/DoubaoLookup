import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - HotKey (Carbon)

    private static var hotKeyRef: EventHotKeyRef?
    private static var hotKeyAction: (() -> Void)?

    private static let hotKeyCallback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, _ in
        DispatchQueue.main.async { hotKeyAction?() }
        return noErr
    }

    private static func registerHotKey(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }; hotKeyRef = nil
        hotKeyAction = action
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x444F5542, id: 1), GetEventDispatcherTarget(), 0, &ref) == noErr else { return }
        hotKeyRef = ref
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyCallback, 1, &type, nil, nil)
    }

    // MARK: - 组件

    private var statusItem: NSStatusItem!
    private var textSelectionManager: TextSelectionManager!
    var floatingWebWindow: FloatingWebWindowController!
    private var settingsWC: SettingsWindowController?
    private var lookupMenuItem: NSMenuItem!
    private var loadingOverlay: LoadingOverlayPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 注册 UserDefaults 默认值
        UserDefaults.standard.register(defaults: [
            "hotkeyKeyCode": 0,  // kVK_ANSI_A
            "hotkeyModifiers": Int(controlKey | optionKey),
            "queryMode": "new",
        ])

        // 状态栏
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button { b.title = "豆"; b.font = .systemFont(ofSize: 13, weight: .medium) }
        statusItem.menu = buildMenu()

        textSelectionManager = TextSelectionManager()
        floatingWebWindow = FloatingWebWindowController()

        // 注册快捷键（从 UserDefaults 读取）
        reloadHotkey()

        // 监听快捷键变更
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotkey), name: .hotkeyDidChange, object: nil)

        textSelectionManager.requestPermissionIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.showWelcomeIfNeeded()
        }
    }

    // MARK: - 快捷键

    @objc private func reloadHotkey() {
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        Self.registerHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.performLookup()
        }
        updateLookupMenuItem()
    }

    private func updateLookupMenuItem() {
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        lookupMenuItem?.title = "查询选中文本  " + Self.hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
    }

    private static func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = [String]()
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0  { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0     { parts.append("⌘") }
        let name = keyName(for: UInt16(truncatingIfNeeded: keyCode)) ?? "KEY-\(keyCode)"
        parts.append(name)
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

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector?) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self; return i
        }
        func checkItem(_ title: String, _ action: Selector?, _ on: Bool) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self; i.state = on ? .on : .off; return i
        }
        menu.addItem(item("显示/隐藏浮窗", #selector(toggleWindow)))
        menu.addItem(NSMenuItem.separator())
        lookupMenuItem = item("查询选中文本  ⌃⌥A", #selector(performLookup))
        menu.addItem(lookupMenuItem!)

        // 查询模式子菜单
        let currentMode = UserDefaults.standard.string(forKey: "queryMode") ?? "new"
        let modeMenu = NSMenu()
        modeMenu.addItem(checkItem("每次新对话", #selector(setModeNew), currentMode == "new"))
        modeMenu.addItem(checkItem("继续上次对话", #selector(setModeContinue), currentMode == "continue"))
        let modeItem = NSMenuItem(title: "查询模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("快捷键设置...", #selector(showSettings)))
        menu.addItem(item("豆包账户...", #selector(showSettings)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("关于豆包查询", #selector(showAbout)))
        menu.addItem(NSMenuItem.separator())
        let q = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(q)
        return menu
    }

    @objc private func setModeNew() {
        UserDefaults.standard.set("new", forKey: "queryMode")
        statusItem.menu = buildMenu()  // 重建菜单刷新勾选状态
    }

    @objc private func setModeContinue() {
        UserDefaults.standard.set("continue", forKey: "queryMode")
        statusItem.menu = buildMenu()
    }

    @objc private func toggleWindow() {
        guard let w = floatingWebWindow else { return }
        if let win = w.window, win.isVisible { win.makeKey(); NSApp.activate(ignoringOtherApps: true) }
        else { w.restore() }
    }

    @objc private func showSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(floatingWC: floatingWebWindow)
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let a = NSAlert(); a.messageText = "豆包查询 v1.0"
        a.informativeText = "选中文本后按快捷键快速查询豆包。\n\n快捷键可在菜单 → 快捷键设置中自定义。"
        a.alertStyle = .informational; a.addButton(withTitle: "关闭"); a.runModal()
    }

    // MARK: - 查询

    @objc func performLookup() {
        guard textSelectionManager.isPermissionGranted else { showPermissionAlert(); return }
        guard let text = textSelectionManager.getSelectedText()?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            showNoSelectionHint(); return
        }

        // 在光标位置显示「正在查询...」逐字动画
        loadingOverlay = LoadingOverlayPanel()
        loadingOverlay.show(at: NSEvent.mouseLocation)

        // 后台加载豆包并发送消息，完成后隐藏动画 + 显示浮窗
        floatingWebWindow.search(query: text) { [weak self] success in
            guard let self = self else { return }
            self.loadingOverlay.dismiss()
            self.loadingOverlay = nil
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.floatingWebWindow.showSearchResult()
                }
            }
        }
    }

    // MARK: - 提示

    private func showPermissionAlert() {
        let a = NSAlert()
        a.messageText = "需要辅助功能权限"
        a.informativeText = "请在「系统设置 → 隐私与安全性 → 辅助功能」中添加本应用。\n如果已添加仍无效，请移除后重新添加。"
        a.alertStyle = .informational; a.addButton(withTitle: "打开系统设置"); a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn { textSelectionManager.requestPermissionIfNeeded() }
    }

    private func showNoSelectionHint() {
        guard !UserDefaults.standard.bool(forKey: "hasShownNoSelectionHint") else { return }
        let a = NSAlert()
        a.messageText = "豆包查询"
        a.informativeText = "未检测到选中的文本。\n请先选中文本再按快捷键查询。"
        a.alertStyle = .informational; a.addButton(withTitle: "不再提示"); a.addButton(withTitle: "知道了")
        if a.runModal() == .alertFirstButtonReturn { UserDefaults.standard.set(true, forKey: "hasShownNoSelectionHint") }
    }

    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasShownWelcome") else { return }
        let a = NSAlert()
        a.messageText = "豆包查询已启动"
        a.informativeText = "使用方式：\n1. 选中文本\n2. 按快捷键查询\n3. 悬浮窗显示豆包结果\n\n⚠️ 首次使用请授权辅助功能权限。\n快捷键可在菜单中自定义。"
        a.alertStyle = .informational; a.addButton(withTitle: "知道了"); a.runModal()
        UserDefaults.standard.set(true, forKey: "hasShownWelcome")
    }
}
