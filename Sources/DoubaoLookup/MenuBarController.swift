import Cocoa

class MenuBarController {

    private var statusItem: NSStatusItem!

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "豆"
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.toolTip = "豆包查询 — ⌃⌥A 查询选中文本"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let lookupItem = NSMenuItem(
            title: "查询选中文本  ⌃⌥A",
            action: #selector(AppDelegate.performLookup),
            keyEquivalent: ""
        )
        lookupItem.target = NSApp.delegate as? AppDelegate
        menu.addItem(lookupItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: "关于豆包查询",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "豆包查询 v1.0"
        alert.informativeText = """
        选中文本后按 ⌃⌥A 快速查询豆包。

        如需修改快捷键，请编辑：
        Sources/DoubaoLookup/AppDelegate.swift
        中的 hotKeyCode 和 hotKeyModifiers 常量。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "关闭")
        alert.runModal()
    }
}
