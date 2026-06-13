import Cocoa
import WebKit

/// 顶部可拖动的标题栏视图
class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 悬浮在鼠标旁的 WKWebView 窗口。
/// 加载 doubao.com 后通过 CGEvent 模拟键盘输入（非 JS 注入）以正确适配 React SPA。
class FloatingWebWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {

    private var webView: WKWebView!
    private var pendingQuery: String?
    private var loadingLabel: NSTextField!
    private var injectionTimer: Timer?

    private static let defaultWindowSize = NSSize(width: 480, height: 600)
    private static let maxRetries = 30
    private static let retryInterval = 0.5

    // ── 初始化 ──

    convenience init() {
        let window = Self.createWindow()
        self.init(window: window)
        setupUI()
    }

    deinit { injectionTimer?.invalidate() }

    // ── 公开接口 ──

    /// 查询豆包
    func search(query: String) {
        if let url = webView.url, url.absoluteString.contains("doubao.com"),
           window?.isVisible == true {
            injectionTimer?.invalidate()
            pendingQuery = query
            updateLoadingMessage("正在查询...")
            startPollingForInput()
            return
        }

        injectionTimer?.invalidate()
        pendingQuery = query
        positionNearMouse()
        window?.delegate = self
        loadingLabel.isHidden = false
        loadingLabel.stringValue = "正在加载..."
        webView.isHidden = true

        showWindow(nil)
        window?.makeKey()
        window?.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)

        if let url = URL(string: "https://www.doubao.com/chat") {
            webView.load(URLRequest(url: url))
        }
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
    }

    /// 显示已关闭的浮窗（不重新加载页面）
    @objc func restore() {
        guard let window = window else { return }
        if window.isVisible {
            window.makeKey(); NSApp.activate(ignoringOtherApps: true)
            return
        }
        positionNearMouse()
        window.delegate = self
        loadingLabel.isHidden = true
        webView.isHidden = false
        window.alphaValue = 1.0
        showWindow(nil)
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeFloatingWindow() {
        injectionTimer?.invalidate()
        injectionTimer = nil
        window?.orderOut(nil)
        window?.alphaValue = 0
        pendingQuery = nil
    }

    // ── 窗口创建 ──

    private static func createWindow() -> NSWindow {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.controlBackgroundColor
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 320, height: 400)
        return window
    }

    private let barHeight: CGFloat = 24

    private func setupUI() {
        guard let v = window?.contentView else { return }
        let webFrame = NSRect(x: 0, y: 0, width: v.bounds.width, height: v.bounds.height - barHeight)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: webFrame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.isHidden = true
        v.addSubview(webView)

        loadingLabel = NSTextField(labelWithString: "正在加载...")
        loadingLabel.font = NSFont.systemFont(ofSize: 15)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.alignment = .center
        loadingLabel.frame = webFrame
        loadingLabel.autoresizingMask = [.width, .height]
        v.addSubview(loadingLabel)

        let handle = DragHandleView(
            frame: NSRect(x: 0, y: v.bounds.height - barHeight, width: v.bounds.width, height: barHeight)
        )
        handle.autoresizingMask = [.width, .minYMargin]
        handle.wantsLayer = true
        handle.layer!.backgroundColor = NSColor.controlBackgroundColor.cgColor
        handle.layer!.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        handle.layer!.borderWidth = 0.5

        let hint = NSTextField(labelWithString: "⠿ 拖拽移动")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = handle.bounds
        hint.autoresizingMask = [.width, .height]
        handle.addSubview(hint)
        v.addSubview(handle)
    }

    // ── 窗口定位 ──

    private func positionNearMouse() {
        guard let window = window else { return }
        let mouseLoc = NSEvent.mouseLocation
        let winSize = window.frame.size
        var x = mouseLoc.x + 20
        var y = mouseLoc.y - winSize.height / 3

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
            let visible = screen.visibleFrame
            x = clamp(x, min: visible.minX + 10, max: visible.maxX - winSize.width - 10)
            y = clamp(y, min: visible.minY + 10, max: visible.maxY - winSize.height - 10)
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // ── WKNavigationDelegate ──

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.absoluteString.contains("doubao.com") == true else { return }
        updateLoadingMessage("正在准备...")
        startPollingForInput()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateLoadingMessage("加载失败")
        showWindowAfterDelay()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateLoadingMessage("无法访问豆包，请检查网络")
        showWindowAfterDelay()
    }

    // ── 查找输入框并聚焦（JS 轮询）──

    private func startPollingForInput() {
        injectionTimer?.invalidate()
        var retries = 0
        injectionTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            retries += 1
            if retries > Self.maxRetries {
                timer.invalidate()
                self.updateLoadingMessage("加载超时，请手动输入")
                self.showWindowAfterDelay()
                return
            }
            self.tryFocusInput()
        }
    }

    private func tryFocusInput() {
        let js = """
        (function() {
            for (var sel of ['textarea','div[contenteditable]','div[role="textbox"]','input[type="text"]']) {
                for (var el of document.querySelectorAll(sel)) {
                    if (el.offsetParent !== null) { el.focus(); el.click(); return true; }
                }
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self, let query = self.pendingQuery, error == nil,
                  let ok = result as? Bool, ok else { return }
            self.injectionTimer?.invalidate()
            self.updateLoadingMessage("正在输入...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.sendTextAndSubmit(query)
            }
        }
    }

    // ── CGEvent 输入 ──

    /// 一次性发送文本 + Enter（不再分块递归）
    private func sendTextAndSubmit(_ text: String) {
        let chars = Array(text.utf16)
        guard let src = CGEventSource(stateID: .hidSystemState),
              let kd = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let ku = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false),
              let ed = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true),
              let eu = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false) else {
            showWindowAfterDelay(); return
        }

        kd.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        ku.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        kd.post(tap: .cghidEventTap)
        usleep(50_000)
        ku.post(tap: .cghidEventTap)
        usleep(100_000)
        ed.post(tap: .cghidEventTap)
        usleep(30_000)
        eu.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateLoadingMessage("等待回答...")
            self.showWindowAfterDelay()
        }
    }

    // ── 窗口显示 ──

    private func updateLoadingMessage(_ msg: String) {
        loadingLabel.stringValue = msg
    }

    private func showWindowAfterDelay() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.window?.animator().alphaValue = 1.0
        }
        loadingLabel.isHidden = true
        webView.isHidden = false
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(value, min), max)
    }
}
