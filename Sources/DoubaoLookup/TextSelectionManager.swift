import Cocoa
import ApplicationServices

/// 通过 macOS 辅助功能 API (AXUIElement) + 剪贴板回退获取当前选中文本。
///
/// Chrome 等浏览器不完全支持 AXSelectedText，因此需要剪贴板方案作为兜底：
/// 保存剪贴板 → 模拟 ⌘C → 读取剪贴板 → 恢复原始内容。
class TextSelectionManager {

    // MARK: - 公开接口

    /// 辅助功能权限是否已授予
    var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 请求权限（弹出系统授权提示框）
    func requestPermissionIfNeeded() {
        guard !isPermissionGranted else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 获取当前前台应用中选中的文本。
    /// 优先使用 AX API，失败时回退到剪贴板方案。
    func getSelectedText() -> String? {
        guard isPermissionGranted else {
            requestPermissionIfNeeded()
            return nil
        }

        // 方案 A: AX API 方式（原生 App 如 Safari、TextEdit 适用）
        if let text = axGetSelectedText() {
            return text
        }

        // 方案 B: 剪贴板回退方式（Chrome、Electron 等适用）
        return clipboardGetSelectedText()
    }

    // MARK: - AX API 方式

    /// 通过 Accessibility API 获取选中文本
    private func axGetSelectedText() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 方案一：直接从应用层获取 AXSelectedText
        if let text = copyAXValue(element: appElement, attribute: kAXSelectedTextAttribute) as? String,
           !text.isEmpty {
            return text
        }

        // 方案二：获取焦点元素，再从焦点元素取选中文本
        if let focused = copyAXValue(element: appElement, attribute: kAXFocusedUIElementAttribute) {
            let focusedElement = focused as! AXUIElement
            if let text = copyAXValue(element: focusedElement, attribute: kAXSelectedTextAttribute) as? String,
               !text.isEmpty {
                return text
            }
        }

        // 方案三：使用系统范围的焦点元素
        let systemWide = AXUIElementCreateSystemWide()
        if let focused = copyAXValue(element: systemWide, attribute: kAXFocusedUIElementAttribute) {
            let focusedElement = focused as! AXUIElement
            if let text = copyAXValue(element: focusedElement, attribute: kAXSelectedTextAttribute) as? String,
               !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func copyAXValue(element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    // MARK: - 剪贴板回退方案

    /// 通过模拟 ⌘C 读取剪贴板获取选中文本
    private func clipboardGetSelectedText() -> String? {
        let pasteboard = NSPasteboard.general

        // 保存当前剪贴板内容（存档为纯数据，避免 NSPasteboardItem 重复写入问题）
        let backup = backupPasteboard(pasteboard)

        // 模拟 ⌘C（使用 C 键 keyCode = 8）
        postCopyEvent()

        // 等待并重试读取剪贴板（某些应用可能需要更长时间）
        for delayMs in [80, 150, 300] {
            usleep(useconds_t(delayMs * 1000))

            guard pasteboard.changeCount != backup.changeCount else { continue }

            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                restorePasteboard(pasteboard, from: backup)
                return text
            }
        }

        // 未读取到文本，恢复剪贴板
        restorePasteboard(pasteboard, from: backup)
        return nil
    }

    /// 发送 ⌘C 按键事件
    private func postCopyEvent() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// 备份剪贴板所有内容为 [PasteboardType: Data] 字典数组
    private func backupPasteboard(_ pasteboard: NSPasteboard) -> (items: [[NSPasteboard.PasteboardType: Data]], changeCount: Int) {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            items.append(itemData)
        }
        return (items, pasteboard.changeCount)
    }

    /// 从备份数据恢复剪贴板
    private func restorePasteboard(_ pasteboard: NSPasteboard, from backup: (items: [[NSPasteboard.PasteboardType: Data]], changeCount: Int)) {
        guard pasteboard.changeCount != backup.changeCount else { return }
        pasteboard.clearContents()
        for itemData in backup.items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
