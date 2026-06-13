import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!
    private var textSelectionManager: TextSelectionManager!
    private var floatingWebWindow: FloatingWebWindowController!

    // ─── 可自定义的快捷键 KeyCode ─────────────────────────────────
    // 常用 KeyCode: A=0, C=8, D=2, E=14, F=3, L=37, Q=12, Space=49
    static let hotKeyCode: UInt32 = 0   // A 键

    // 修饰键组合 (Carbon 常量): cmdKey=0x0100, shiftKey=0x0200, optionKey=0x0800, controlKey=0x0400
    static let hotKeyModifiers: UInt32 = UInt32(controlKey | optionKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用（无 Dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 初始化各模块
        menuBarController = MenuBarController()
        textSelectionManager = TextSelectionManager()
        floatingWebWindow = FloatingWebWindowController()

        // 注册全局快捷键
        HotKeyManager.register(
            keyCode: Self.hotKeyCode,
            modifiers: Self.hotKeyModifiers
        ) { [weak self] in
            self?.performLookup()
        }

        // 请求辅助功能权限（获取选中文本需要）
        textSelectionManager.requestPermissionIfNeeded()

        // 首次启动提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showWelcomeIfNeeded()
        }
    }

    /// 执行查询：获取选中文本 → 打开悬浮窗 → 发豆包
    @objc func performLookup() {
        guard let selectedText = textSelectionManager.getSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNoSelectionNotification()
            return
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        floatingWebWindow.search(query: trimmed)
    }

    // MARK: - 通知 / 提示

    private func showNoSelectionNotification() {
        let alert = NSAlert()
        alert.messageText = "豆包查询"
        alert.informativeText = "未检测到选中的文本。\n请先选中文本再按 ⌃⌥A 查询。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        if let window = floatingWebWindow.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func showWelcomeIfNeeded() {
        let hasShownWelcome = UserDefaults.standard.bool(forKey: "hasShownWelcome")
        guard !hasShownWelcome else { return }

        let alert = NSAlert()
        alert.messageText = "豆包查询已启动"
        alert.informativeText = """
        使用方式：
        1. 在任何应用中选中文本
        2. 按 ⌃⌥A（Control + Option + A）
        3. 悬浮窗将显示豆包的查询结果

        ⚠️ 首次使用时，请在「系统设置 → 隐私与安全性 → 辅助功能」
        中添加本应用以授予权限。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()

        UserDefaults.standard.set(true, forKey: "hasShownWelcome")
    }
}
