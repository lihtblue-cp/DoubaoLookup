import Cocoa
import WebKit

/// 顶部可拖动的标题栏视图
class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 悬浮在鼠标旁的 WKWebView 窗口。
///
/// 加载 doubao.com 后，通过 CGEvent 模拟真实键盘输入（而不是 JS 注入），
/// 这样 React SPA 会正确响应。最后隐藏加载过程、支持点击外部关闭。
class FloatingWebWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {

    private var webView: WKWebView!
    private var pendingQuery: String?
    private var loadingLabel: NSTextField!
    private var injectionTimer: Timer?

    private static let defaultWindowSize = NSSize(width: 480, height: 600)
    private static let maxRetries = 30           // 最多等 15 秒（React 渲染）
    private static let retryInterval = 0.5       // 每 500ms 查一次

    // ── 初始化 ────────────────────────────────────────────────────

    convenience init() {
        let window = Self.createWindow()
        self.init(window: window)
        setupWebView()
        setupLoadingLabel()
        setupDragHandle()
    }

    deinit {
        injectionTimer?.invalidate()
    }

    // ── 公开接口 ──────────────────────────────────────────────────

    /// 用 query 查询豆包
    func search(query: String) {
        // 如果豆包已加载，直接聚焦 + 输入（不重刷页面）
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

        // 初始：隐藏窗口
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

    // ── NSWindowDelegate（点击外部关闭）─────────────────────────────

    func windowDidResignKey(_ notification: Notification) {
        closeFloatingWindow()
    }

    // ── 窗口创建 ──────────────────────────────────────────────────

    private static func createWindow() -> NSWindow {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
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

    private func setupWebView() {
        guard let contentView = window?.contentView else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - barHeight),
            configuration: config
        )
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.isHidden = true
        contentView.addSubview(webView)
    }

    private func setupLoadingLabel() {
        guard let contentView = window?.contentView else { return }
        loadingLabel = NSTextField(labelWithString: "正在加载...")
        loadingLabel.font = NSFont.systemFont(ofSize: 15)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.alignment = .center
        loadingLabel.frame = NSRect(
            x: 0, y: 0,
            width: contentView.bounds.width, height: contentView.bounds.height - barHeight
        )
        loadingLabel.autoresizingMask = [.width, .height]
        contentView.addSubview(loadingLabel)
    }

    private func setupDragHandle() {
        guard let contentView = window?.contentView else { return }
        let dragHandle = DragHandleView(
            frame: NSRect(x: 0, y: contentView.bounds.height - barHeight, width: contentView.bounds.width, height: barHeight)
        )
        dragHandle.autoresizingMask = [.width, .minYMargin]
        dragHandle.wantsLayer = true
        // 半透明背景，带分隔线
        let layer = dragHandle.layer!
        layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        layer.borderWidth = 0.5

        // 拖拽提示文字
        let hint = NSTextField(labelWithString: "⠿ 拖拽移动")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = NSColor.secondaryLabelColor
        hint.alignment = .center
        hint.frame = dragHandle.bounds
        hint.autoresizingMask = [.width, .height]
        dragHandle.addSubview(hint)

        contentView.addSubview(dragHandle)
    }

    // ── 窗口定位 ──────────────────────────────────────────────────

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

    // ── WKNavigationDelegate ──────────────────────────────────────

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let pageURL = webView.url?.absoluteString else { return }

        guard pageURL.contains("doubao.com") else {
            updateLoadingMessage("非豆包页面: \(pageURL)")
            return
        }

        updateLoadingMessage("正在准备...")
        startPollingForInput()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateLoadingMessage("加载失败: \(error.localizedDescription)")
        showWindowAfterDelay()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateLoadingMessage("无法访问豆包，请检查网络连接。")
        showWindowAfterDelay()
    }

    // ── 查找输入框并聚焦（JS 轮询）─────────────────────────────────

    private func startPollingForInput() {
        injectionTimer?.invalidate()

        var retries = 0
        injectionTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            retries += 1
            if retries > Self.maxRetries {
                timer.invalidate()
                self.updateLoadingMessage("加载超时，请手动输入。")
                self.showWindowAfterDelay()
                return
            }

            self.tryFocusInput(retry: retries)
        }
    }

    /// 尝试通过 JS 查找并聚焦输入框
    private func tryFocusInput(retry: Int) {
        let js = """
        (function() {
            // 找到页面上可见的输入框
            var selectors = [
                'textarea', 'div[contenteditable="true"]', 'div[role="textbox"]',
                '[contenteditable]', 'input[type="text"]',
                'div[data-testid*="input"]', '[class*="input-area"]',
                '[class*="chat-input"]', '[class*="composer"]'
            ];
            for (var sel of selectors) {
                var els = document.querySelectorAll(sel);
                for (var el of els) {
                    if (el.offsetParent !== null) {
                        var r = el.getBoundingClientRect();
                        if (r.width > 10 && r.height > 10) {
                            el.focus();
                            el.click();
                            return JSON.stringify({ok: true, tag: el.tagName, cls: (el.className || '').substring(0,150)});
                        }
                    }
                }
            }
            return JSON.stringify({ok: false});
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self, let query = self.pendingQuery else { return }

            if let error = error {
                print("[Focus] 错误: \(error.localizedDescription)")
                return
            }

            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = dict["ok"] as? Bool else {
                return
            }

            if ok {
                print("[Focus] 成功聚焦: \(dict["tag"] ?? "") \(dict["cls"] ?? "")")
                self.injectionTimer?.invalidate()
                self.updateLoadingMessage("正在输入...")

                // 用 CGEvent 模拟真实键盘输入
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.typeTextWithCGEvent(query)
                }
            } else if retry % 5 == 0 {
                // 每 5 次输出 DOM 诊断
                self.exploreDOM()
            }
        }
    }

    /// 输出页面 DOM 诊断信息
    private func exploreDOM() {
        let js = """
        JSON.stringify(Array.from(document.querySelectorAll('*')).filter(function(el) {
            return el.offsetParent !== null && el.getBoundingClientRect().width > 0;
        }).map(function(el) {
            var r = el.getBoundingClientRect();
            return {tag: el.tagName, id: el.id, cls: (el.className||'').substring(0,80),
                    role: el.getAttribute('role')||'', editable: el.getAttribute('contenteditable')||'',
                    w: Math.round(r.width), h: Math.round(r.height), t: Math.round(r.top)};
        }).filter(function(el) {
            return ['TEXTAREA','INPUT'].includes(el.tag) || el.editable === 'true' || el.role === 'textbox';
        }));
        """
        webView.evaluateJavaScript(js) { result, _ in
            print("[DOM] \(result ?? "no result")")
        }
    }

    // ── CGEvent 异步分段输入 ──────────────────────────────────────

    /// 用 CGEvent 分段输入文本（每段 5 字符，异步不阻塞主线程）
    private func typeTextWithCGEvent(_ text: String) {
        let chars = Array(text.utf16)
        typeChunk(chars: chars, index: 0)
    }

    /// 递归异步发送一段字符，完成后验证+Enter
    private func typeChunk(chars: [UniChar], index: Int) {
        guard index < chars.count else {
            verifyThenEnter()
            return
        }

        let end = min(index + 5, chars.count)
        let chunk = Array(chars[index..<end])

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            // 跳过这一批继续
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.typeChunk(chars: chars, index: end)
            }
            return
        }

        down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
        up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
        down.post(tap: .cghidEventTap)
        usleep(15_000)
        up.post(tap: .cghidEventTap)

        // 异步调度下一段（不阻塞主线程）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.typeChunk(chars: chars, index: end)
        }
    }

    /// 验证输入框内容是否完整，不足则补打
    private func verifyThenEnter() {
        // 小等待确保最后一段已处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.webView.evaluateJavaScript(
                "document.activeElement ? (document.activeElement.value || document.activeElement.textContent || '') : ''"
            ) { [weak self] result, _ in
                guard let self = self else { return }
                let current = (result as? String) ?? ""

                // 如果内容比预期短，补打剩余部分
                if let pendingQuery = self.pendingQuery, current.count < pendingQuery.count {
                    let missing = String(pendingQuery.dropFirst(current.count))
                    print("[输入] 补打 \(missing.count) 个字符")
                    // 去掉 usleep，直接用异步方式打
                    self.typeTextWithCGEvent(missing)
                    return
                }

                // 内容完整，按 Enter
                self.pressEnterAndShow()
            }
        }
    }

    /// 按 Enter + 显示窗口
    private func pressEnterAndShow() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            showWindowAfterDelay()
            return
        }
        keyDown.post(tap: .cghidEventTap)
        usleep(30_000)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateLoadingMessage("等待回答...")
            self.showWindowAfterDelay()
        }
    }

    // ── 窗口显示控制 ──────────────────────────────────────────────

    private func updateLoadingMessage(_ msg: String) {
        DispatchQueue.main.async {
            self.loadingLabel.stringValue = msg
        }
    }

    /// 淡入显示窗口
    private func showWindowAfterDelay() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.window?.animator().alphaValue = 1.0
            }
            self.loadingLabel.isHidden = true
            self.webView.isHidden = false
        }
    }

    // ── 关闭 ──────────────────────────────────────────────────────

    @objc func closeFloatingWindow() {
        injectionTimer?.invalidate()
        injectionTimer = nil
        window?.orderOut(nil)
        window?.alphaValue = 0
        pendingQuery = nil
    }

    // ── 工具 ──────────────────────────────────────────────────────

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(value, min), max)
    }
}
