APP_NAME = 豆包查询.app
BUILD_DIR = .build

.PHONY: all build app run clean

all: app

# 编译 Release 版本
build:
	swift build -c release

# 创建 .app  bundle
app: build
	rm -rf "$(APP_NAME)"
	mkdir -p "$(APP_NAME)/Contents/MacOS"
	mkdir -p "$(APP_NAME)/Contents/Resources"
	cp Resources/Info.plist "$(APP_NAME)/Contents/"
	cp "$(BUILD_DIR)/release/DoubaoLookup" "$(APP_NAME)/Contents/MacOS/"
	# 用 ad-hoc 签名（开发环境必需，否则辅助功能权限可能不生效）
	codesign --force --deep --sign - "$(APP_NAME)" 2>/dev/null || true
	@echo ""
	@echo "✅ $(APP_NAME) 构建完成！"

# 构建并运行
run: app
	open "$(APP_NAME)"

# 清理
clean:
	rm -rf "$(BUILD_DIR)"
	rm -rf "$(APP_NAME)"
