import Cocoa
import ApplicationServices

/// 通过 AX API + 剪贴板回退获取选中文本
class TextSelectionManager {

    var isPermissionGranted: Bool { AXIsProcessTrusted() }

    func requestPermissionIfNeeded() {
        guard !isPermissionGranted else { return }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary)
    }

    func getSelectedText() -> String? {
        guard isPermissionGranted else { requestPermissionIfNeeded(); return nil }
        return axGetSelectedText() ?? clipboardGetSelectedText()
    }

    // MARK: - AX API

    private func axGetSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)

        // 直接取值
        if let s = axCopy(el, kAXSelectedTextAttribute as CFString) as? String, !s.isEmpty { return s }
        // 通过焦点元素
        if let v = axCopy(el, kAXFocusedUIElementAttribute as CFString) {
            let f = v as! AXUIElement
            if let s = axCopy(f, kAXSelectedTextAttribute as CFString) as? String, !s.isEmpty { return s }
        }
        // 系统级焦点元素
        let sys = AXUIElementCreateSystemWide()
        if let v = axCopy(sys, kAXFocusedUIElementAttribute as CFString) {
            let f = v as! AXUIElement
            if let s = axCopy(f, kAXSelectedTextAttribute as CFString) as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private func axCopy(_ el: AXUIElement, _ attr: CFString) -> CFTypeRef? {
        var v: CFTypeRef?; return AXUIElementCopyAttributeValue(el, attr, &v) == .success ? v : nil
    }

    // MARK: - 剪贴板回退（模拟 ⌘C）

    private func clipboardGetSelectedText() -> String? {
        let pb = NSPasteboard.general
        let backup = pb.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { d in (t, d) } })
        } ?? []
        let oldCC = pb.changeCount

        guard let kd = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true),
              let ku = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false) else { return nil }
        kd.flags = .maskCommand; ku.flags = .maskCommand
        kd.post(tap: .cghidEventTap); ku.post(tap: .cghidEventTap)

        for ms in [30, 80, 150] {
            usleep(useconds_t(ms * 1000))
            guard pb.changeCount != oldCC, let text = pb.string(forType: .string), !text.isEmpty else { continue }
            restore(pb, backup, oldCC); return text
        }
        restore(pb, backup, oldCC); return nil
    }

    private func restore(_ pb: NSPasteboard, _ data: [[NSPasteboard.PasteboardType: Data]], _ cc: Int) {
        guard pb.changeCount != cc else { return }
        pb.clearContents()
        for itemData in data {
            let item = NSPasteboardItem()
            itemData.forEach { item.setData($1, forType: $0) }
            pb.writeObjects([item])
        }
    }
}
