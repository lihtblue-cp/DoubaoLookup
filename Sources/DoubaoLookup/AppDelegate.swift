import Cocoa
import Carbon

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!
    private var textSelectionManager: TextSelectionManager!
    var floatingWebWindow: FloatingWebWindowController!

    // ─── 可自定义的快捷键 KeyCode ─────────────────────────────────
    // 常用 KeyCode: A=0, C=8, D=2, E=14, F=3, L=37, Q=12, Space=49
    static let hotKeyCode: UInt32 = 0   // A 键

    // 修饰键组合 (Carbon 常量): cmdKey=0x0100, shiftKey=0x0200, optionKey=0x0800, controlKey=0x0400
    static let hotKeyModifiers: UInt32 = UInt32(controlKey | optionKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用（无 Dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 初始化各模块
        menuBarController = MenuBarController(appDelegate: self)
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
        // 1. 检查辅助功能权限（未授权时只弹权限窗，不弹其他窗）
        guard textSelectionManager.isPermissionGranted else {
            showPermissionAlert()
            return
        }

        // 2. 获取选中文本
        guard let selectedText = textSelectionManager.getSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNoSelectionNotification()
            return
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        floatingWebWindow.search(query: trimmed)
    }

    // MARK: - 提示

    /// 权限未授权时的引导提示（只弹这一个，不连锁弹窗）
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        豆包查询需要「辅助功能」权限来读取选中的文本。

        请在系统设置中确保已添加本应用：
        系统设置 → 隐私与安全性 → 辅助功能

        如果已添加但仍无法使用，请尝试：
        1. 在列表中移除本应用
        2. 点击下方按钮，重新授权
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            textSelectionManager.requestPermissionIfNeeded()
        }
    }

    /// 未选中文本时的提示
    private func showNoSelectionNotification() {
        // 检查是否已提示过，避免每次按快捷键都弹窗
        let hasShown = UserDefaults.standard.bool(forKey: "hasShownNoSelectionHint")
        if hasShown { return }

        let alert = NSAlert()
        alert.messageText = "豆包查询"
        alert.informativeText = "未检测到选中的文本。\n请先选中文本再按 ⌃⌥A 查询。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "不再提示")
        alert.addButton(withTitle: "知道了")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(true, forKey: "hasShownNoSelectionHint")
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
