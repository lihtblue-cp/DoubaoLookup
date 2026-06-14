# 豆包查询 — DoubaoLookup

> macOS 菜单栏工具 · 选中文本一键查询豆包 AI

选中任意文本，按下快捷键即可在悬浮窗口中查询豆包，无需手动复制粘贴、打开浏览器。

---

## 功能

- **全局快捷键** — 选中文本后按自定义快捷键，自动查询豆包
- **悬浮浮窗** — 豆包结果以内置 WebView 浮窗显示，随鼠标位置定位
- **逐字动画** — 按下快捷键时在光标位置显示"正在查询..."动画，查询完成后自动消失
- **两种查询模式** — "每次新对话" 或 "继续上次对话"
- **快捷键自定义** — 内置快捷键录制器，支持冲突检测
- **菜单栏常驻** — 状态栏图标切换浮窗，不干扰其他工作

## 系统要求

- macOS 13+ (Ventura)
- Xcode Command Line Tools（`xcode-select --install`）
- 辅助功能权限（首次使用会自动提示授权）

## 构建 & 运行

```bash
# 克隆项目
git clone https://github.com/lihtblue-cp/DoubaoLookup.git
cd DoubaoLookup

# （推荐）创建本地签名证书，避免每次重编译丢失辅助功能权限
make setup-signing

# 构建并运行
make run
```

首次启动后，根据提示在 **系统设置 → 隐私与安全性 → 辅助功能** 中授予权限。

## 使用说明

1. 在任意应用中选中文本
2. 按快捷键（默认 `⌃⌥A`）查询
3. 浮窗自动显示豆包回答

可在菜单栏 **豆 → 查询模式** 切换"新对话"或"继续对话"模式。

## 快捷键设置

菜单栏 **豆 → 快捷键设置** 打开设置窗口：

- 点击录制区域，按下新的快捷键组合
- 如快捷键被系统或常用应用占用，会弹出冲突警告
- 设置成功后显示绿色"✓ 设置成功"提示

## 项目结构

```
Sources/DoubaoLookup/
├── main.swift                       # 应用入口
├── AppDelegate.swift                # 应用代理、快捷键、菜单
├── FloatingWebWindowController.swift # 悬浮 WebView 浮窗
├── LoadingOverlayPanel.swift        # 光标位置"正在查询..."动画
├── SettingsWindowController.swift   # 设置窗口（快捷键录制、账户管理）
└── TextSelectionManager.swift       # AX API + 剪贴板获取选中文本
Resources/
└── Info.plist                       # 应用配置
Makefile                             # 构建脚本
Package.swift                        # SPM 配置
```

## 技术栈

- **语言:** Swift
- **框架:** AppKit, WebKit, Carbon (HotKey), ApplicationServices (AX API)
- **构建:** Swift Package Manager (5.9+)
- **无外部依赖**

## 许可

MIT
