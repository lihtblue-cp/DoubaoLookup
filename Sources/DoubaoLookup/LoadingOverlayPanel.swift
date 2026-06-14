import Cocoa

/// 跟随光标的「正在查询...」逐字动画面板
class LoadingOverlayPanel: NSPanel {

    private var textField: NSTextField!
    private var cycleTimer: Timer?
    private let baseText = "正在查询"
    private let dots = [".", "..", "..."]
    private var phase = 0

    init() {
        let size = NSSize(width: 90, height: 26)
        let rect = NSRect(origin: .zero, size: size)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 纯文字，无背景
        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        contentView = container

        textField = NSTextField(labelWithString: baseText)
        textField.font = NSFont.menuFont(ofSize: 9)
        textField.textColor = .labelColor
        textField.alignment = .center
        textField.frame = rect.insetBy(dx: 6, dy: 3)
        textField.autoresizingMask = [.width, .height]
        container.addSubview(textField)
    }

    required init?(coder: NSCoder) { nil }

    /// 在指定屏幕位置显示并开始动画
    func show(at point: NSPoint) {
        let size = frame.size
        setFrameOrigin(NSPoint(x: point.x - size.width / 2,
                               y: point.y - size.height - 20))
        orderFrontRegardless()
        startAnimating()
    }

    /// 停止动画并隐藏
    func dismiss() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        orderOut(nil)
    }

    // MARK: - 动画

    private func startAnimating() {
        phase = 0
        updateText()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updateText()
        }
    }

    /// 逐字显示 → 加点循环
    /// "正" → "正在" → "正在查" → "正在查询" → "正在查询." → "正在查询.." → "正在查询..." → "正" → ...
    private func updateText() {
        let chars = Array(baseText)
        if phase < chars.count {
            textField.stringValue = String(chars[0...phase])
        } else {
            let dotIndex = (phase - chars.count) % 3
            textField.stringValue = baseText + dots[dotIndex]
        }
        phase = (phase + 1) % (chars.count + 3)
    }
}
