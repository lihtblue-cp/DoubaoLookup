import Cocoa
import WebKit

/// 顶部可拖动的标题栏视图
class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 悬浮在鼠标旁的 WKWebView 窗口。
class FloatingWebWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {

    private var webView: WKWebView!
    private var pendingQuery: String?
    private var injectionTimer: Timer?
    private var pageLoaded = false
    private var searchCompletion: ((Bool) -> Void)?

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

    var webViewForCookieStore: WKWebView? { webView }

    /// 查询豆包（后台执行，完成后通过 completion 回调）
    func search(query: String, completion: @escaping (Bool) -> Void = { _ in }) {
        injectionTimer?.invalidate()
        pendingQuery = query
        window?.delegate = self
        searchCompletion = completion
        let mode = UserDefaults.standard.string(forKey: "queryMode") ?? "new"

        // 预先定位窗口（暂不显示）
        if let win = window, !win.isVisible {
            positionNearMouse()
            win.alphaValue = 1.0
        }

        if mode == "continue" && pageLoaded {
            // 继续对话：不重刷页面，直接注入
            tryFocusInput()
        } else {
            // 新对话（或首次加载）：重刷页面
            pageLoaded = false
            if let url = URL(string: "https://www.doubao.com/chat") {
                var req = URLRequest(url: url)
                req.cachePolicy = .returnCacheDataElseLoad
                webView.load(req)
            }
        }
    }

    /// 查询完成后显示浮窗
    func showSearchResult() {
        guard let win = window else { return }
        positionNearMouse()
        win.alphaValue = 1.0
        win.delegate = self
        win.orderFrontRegardless()
        win.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
    }

    @objc func restore() {
        guard let win = window else { return }
        if win.isVisible {
            win.makeKey(); NSApp.activate(ignoringOtherApps: true)
            return
        }
        positionNearMouse()
        win.delegate = self
        win.alphaValue = 1.0
        win.orderFrontRegardless()
        win.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeFloatingWindow() {
        injectionTimer?.invalidate()
        injectionTimer = nil
        window?.orderOut(nil)
        window?.alphaValue = 0
        pendingQuery = nil
    }

    // ── 导航到登录页 ──

    func navigateToLogin() {
        if let url = URL(string: "https://www.doubao.com/chat") {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(req)
        }
        // 显示窗口让用户看到登录页
        showSearchResult()
    }

    func clearCookies(completion: @escaping () -> Void = {}) {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                           for: records,
                           completionHandler: completion)
        }
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

    private let barHeight: CGFloat = 28

    private func setupUI() {
        guard let v = window?.contentView else { return }
        let webFrame = NSRect(x: 0, y: 0, width: v.bounds.width, height: v.bounds.height - barHeight)

        // WebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: webFrame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        v.addSubview(webView)

        // ── 拖动条 ──
        let barFrame = NSRect(x: 0, y: v.bounds.height - barHeight, width: v.bounds.width, height: barHeight)
        let bar = DragHandleView(frame: barFrame)
        bar.autoresizingMask = [.width, .minYMargin]
        bar.wantsLayer = true
        bar.layer!.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let line = NSView(frame: NSRect(x: 0, y: 0, width: barFrame.width, height: 0.5))
        line.wantsLayer = true
        line.layer!.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        line.autoresizingMask = [.width, .maxYMargin]
        bar.addSubview(line)

        let hint = NSTextField(labelWithString: "⠿ 拖拽移动")
        hint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 0, width: barFrame.width - 40, height: barFrame.height)
        hint.autoresizingMask = [.width, .height]
        bar.addSubview(hint)

        let closeBtn = NSButton(frame: NSRect(x: barFrame.width - 24, y: (barFrame.height - 16) / 2, width: 16, height: 16))
        closeBtn.autoresizingMask = [.minXMargin]
        closeBtn.bezelStyle = .circular
        closeBtn.isBordered = false
        closeBtn.title = ""
        closeBtn.toolTip = "关闭"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: attrs)
        closeBtn.target = self
        closeBtn.action = #selector(closeFloatingWindow)
        bar.addSubview(closeBtn)

        v.addSubview(bar)
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
        pageLoaded = true
        startPollingForInput()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completeSearch(success: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completeSearch(success: false)
    }

    // ── 查找输入框并聚焦（JS 轮询）──

    private func startPollingForInput() {
        injectionTimer?.invalidate()
        var retries = 0
        tryFocusInput()
        injectionTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            retries += 1
            if retries > Self.maxRetries {
                timer.invalidate()
                self.completeSearch(success: false)
                return
            }
            self.tryFocusInput()
        }
    }

    private func tryFocusInput() {
        let js = """
        (function() {
            var el = document.activeElement;
            if (el && el !== document.body && el !== document.documentElement) {
                if (el.offsetParent !== null) {
                    el.focus(); return el.tagName;
                }
            }
            for (var sel of ['textarea','div[contenteditable]','div[role="textbox"]','input[type="text"]']) {
                for (var e of document.querySelectorAll(sel)) {
                    if (e.offsetParent !== null) { e.focus(); e.click(); return e.tagName; }
                }
            }
            return '';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self, let query = self.pendingQuery, error == nil,
                  let tag = result as? String, !tag.isEmpty else { return }
            self.injectionTimer?.invalidate()
            self.window?.makeFirstResponder(self.webView)

            // 统一使用 JS 注入（execCommand 生成 trusted input 事件）
            self.injectTextViaJS(query)
        }
    }

    // ── JS 注入文字 + 按钮点击（两种模式通用）──

    private func injectTextViaJS(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "'", with: "\\'")
                          .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        (function() {
            var t = '\(escaped)';
            var el = document.querySelector('div[contenteditable]') ||
                     document.querySelector('textarea') ||
                     document.querySelector('div[role="textbox"]');
            if (!el || el.offsetParent === null) return 'no-input';

            el.focus();

            // 清空已有内容
            if (el.isContentEditable) { el.textContent = ''; }
            else { el.value = ''; }

            // execCommand 生成 trusted input 事件 → React onChange
            try {
                document.execCommand('insertText', false, t);
            } catch(e) {
                if (el.isContentEditable) { el.textContent = t; }
                else { el.value = t; }
                el.dispatchEvent(new Event('input', {bubbles: true}));
            }

            return 'text-inserted';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            let r = result as? String ?? ""
            if error != nil || r == "no-input" {
                self.fallbackToReload()
                return
            }

            // 等待 React 处理，然后找发送按钮点击（最多重试 20 次）
            self.tryClickSendButton(retries: 20) { success in
                if success {
                    self.completeSearch(success: true)
                } else {
                    // 回退到 CGEvent Enter
                    self.fallbackToCGEventEnter()
                }
            }
        }
    }

    // ── CGEvent Enter 回退 ──

    private func fallbackToCGEventEnter() {
        guard let ed = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true),
              let eu = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false) else {
            completeSearch(success: false)
            return
        }
        // CGEvent 需要窗口激活
        showSearchResult()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ed.post(tap: .cgAnnotatedSessionEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                eu.post(tap: .cgAnnotatedSessionEventTap)
                self.completeSearch(success: true)
            }
        }
    }

    /// 轮询查找发送按钮并点击（最多 20 次，每次间隔 100ms）
    private func tryClickSendButton(retries: Int, completion: @escaping (Bool) -> Void) {
        guard retries > 0 else { completion(false); return }

        let js = """
        (function() {
            var btns = document.querySelectorAll('button');
            for (var i = 0; i < btns.length; i++) {
                var b = btns[i];
                if (b.offsetParent === null || b.disabled) continue;
                var a = (b.getAttribute('aria-label') || '').toLowerCase();
                var c = (b.textContent || '').trim().toLowerCase();
                var d = (b.getAttribute('data-testid') || '').toLowerCase();
                if (a.includes('发送') || a.includes('send') ||
                    c === '发送' || c === 'send' || c === '↵' ||
                    d.includes('send') || d.includes('submit')) {
                    b.click();
                    return 'clicked';
                }
            }
            var all = document.querySelectorAll('[role="button"], [class*="send"], [class*="发送"], [class*="submit"]');
            for (var i = 0; i < all.length; i++) {
                var el = all[i];
                if (el.tagName === 'BUTTON') continue;
                if (el.offsetParent === null || el.disabled) continue;
                var a = (el.getAttribute('aria-label') || '').toLowerCase();
                var c = (el.textContent || '').trim().toLowerCase();
                if (a.includes('发送') || a.includes('send') || c === '发送' || c === 'send') {
                    el.click();
                    return 'clicked-alt';
                }
            }
            return 'not-found';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if error != nil { completion(false); return }
            let r = result as? String ?? ""
            if r == "clicked" || r == "clicked-alt" {
                completion(true)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.tryClickSendButton(retries: retries - 1, completion: completion)
            }
        }
    }

    /// 回退：重置并重刷页面
    private func fallbackToReload() {
        pageLoaded = false
        guard let query = pendingQuery else { return }
        DispatchQueue.main.async { [weak self] in
            self?.search(query: query, completion: self?.searchCompletion ?? { _ in })
        }
    }

    // MARK: - 完成回调

    private func completeSearch(success: Bool) {
        searchCompletion?(success)
        searchCompletion = nil
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(value, min), max)
    }
}
