import Carbon

/// 使用 Carbon 的 RegisterEventHotKey 注册全局快捷键。
/// 注意：本 API 会消费按键事件，不会透传到前台应用，因此不会影响其他应用的快捷键使用。
class HotKeyManager {

    private static var hotKeyRef: EventHotKeyRef?
    private static var eventHandlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    /// 非捕获型 C 回调（不能是闭包，因为 @convention(c) 不能捕获上下文）
    private static let eventCallback: @convention(c) (
        EventHandlerCallRef?,
        EventRef?,
        UnsafeMutableRawPointer?
    ) -> OSStatus = { _, _, _ in
        DispatchQueue.main.async {
            HotKeyManager.action?()
        }
        return noErr
    }

    /// 注册一个全局快捷键
    /// - Parameters:
    ///   - keyCode: 按键的 KeyCode（如 L = 37）
    ///   - modifiers: 修饰键组合 Carbon 常量（cmdKey | shiftKey | optionKey | controlKey）
    ///   - action: 按下快捷键时执行的回调（主线程执行）
    /// - Returns: 是否注册成功
    @discardableResult
    static func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> Bool {
        unregister()
        Self.action = action

        let hotKeyID = EventHotKeyID(signature: 0x444F5542, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else {
            print("[HotKey] 注册失败: \(status)")
            return false
        }
        Self.hotKeyRef = ref

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.eventCallback,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installStatus == noErr else {
            print("[HotKey] 事件处理器安装失败: \(installStatus)")
            UnregisterEventHotKey(ref)
            Self.hotKeyRef = nil
            return false
        }
        Self.eventHandlerRef = handlerRef

        print("[HotKey] 全局快捷键注册成功")
        return true
    }

    /// 注销快捷键
    static func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        action = nil
    }
}
