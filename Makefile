APP_NAME = 豆包查询.app
BUILD_DIR = .build
SIGN_ID = DoubaoLookupDev

.PHONY: all build app run clean setup-signing

all: app

build:
	swift build -c release

# 创建持久化本地签名证书（仅需执行一次）
# 使每次构建用同一身份签名，避免 macOS 辅助功能权限丢失
setup-signing:
	@TF=$$(mktemp); if codesign --sign "$(SIGN_ID)" "$$TF" 2>/dev/null; then \
		rm -f "$$TF"; echo "✅ 证书 $(SIGN_ID) 已存在"; exit 0; \
	fi; rm -f "$$TF"; \
	echo "创建本地签名证书 $(SIGN_ID) ..."; \
	DIR=$$(mktemp -d); \
	printf '%s\n' \
		'[req]' 'distinguished_name=dn' 'prompt=no' 'x509_extensions=ext' \
		'[dn]' 'CN=$(SIGN_ID)' \
		'[ext]' 'basicConstraints=critical,CA:TRUE' 'keyUsage=critical,digitalSignature' 'extendedKeyUsage=codeSigning' \
		> "$$DIR/conf"; \
	openssl req -x509 -nodes -newkey rsa:2048 \
		-config "$$DIR/conf" \
		-keyout "$$DIR/cert.key" \
		-out "$$DIR/cert.pem" \
		-days 3650 2>/dev/null; \
	openssl pkcs12 \
		-provider legacy -provider default -legacy -export \
		-inkey "$$DIR/cert.key" -in "$$DIR/cert.pem" \
		-out "$$DIR/cert.p12" \
		-passout pass:temppass 2>/dev/null; \
	security import "$$DIR/cert.p12" \
		-k ~/Library/Keychains/login.keychain-db \
		-P "temppass" -T /usr/bin/codesign -A 2>/dev/null; \
	rm -rf "$$DIR"; \
	echo "✅ 证书 $(SIGN_ID) 创建成功，辅助功能权限将持续有效"

# 创建 .app bundle
app: build
	rm -rf "$(APP_NAME)"
	mkdir -p "$(APP_NAME)/Contents/MacOS"
	mkdir -p "$(APP_NAME)/Contents/Resources"
	cp Resources/Info.plist "$(APP_NAME)/Contents/"
	cp "$(BUILD_DIR)/release/DoubaoLookup" "$(APP_NAME)/Contents/MacOS/"
	# 用持久证书签名 → 身份跨构建不变 → 权限不丢失
	TF=$$(mktemp); \
	if codesign --sign "$(SIGN_ID)" "$$TF" 2>/dev/null; then \
		rm -f "$$TF"; \
		codesign --force --deep --sign "$(SIGN_ID)" "$(APP_NAME)"; \
		echo "✅ 已用 $(SIGN_ID) 签名"; \
	else \
		rm -f "$$TF"; \
		codesign --force --deep --sign - "$(APP_NAME)"; \
		echo "⚠️  证书 $(SIGN_ID) 未安装，使用 ad-hoc 签名"; \
		echo "   建议执行 make setup-signing 安装持久证书"; \
	fi
	@echo "✅ $(APP_NAME) 构建完成！"

run: app
	open "$(APP_NAME)"

# 发布新版本
# 用法: make release VERSION=1.2
# 该命令会：构建 app → 打包 DMG → 创建 GitHub Release 并上传
release: app
	@if [ -z "$(VERSION)" ]; then echo "用法: make release VERSION=x.y"; exit 1; fi
	@DIR=$$(mktemp -d); \
		cp -R "$(APP_NAME)" "$$DIR/"; \
		ln -s /Applications "$$DIR/Applications"; \
		hdiutil create -volname "豆包查询" -srcfolder "$$DIR" -ov -format UDZO "豆包查询.dmg" 2>/dev/null; \
		rm -rf "$$DIR"
	@echo "✅ DMG 打包完成"
	git tag -f "$(VERSION)"
	git push origin "$(VERSION)" -f
	@echo "✅ 标签 $(VERSION) 已推送"
	gh release create "$(VERSION)" \
		--title "豆包查询 v$(VERSION)" \
		--notes "请参见 README.md 了解更新内容。" \
		"豆包查询.dmg#DoubaoLookup_Mac.dmg"
	@echo "✅ Release v$(VERSION) 已发布"

clean:
	rm -rf "$(BUILD_DIR)"
	rm -rf "$(APP_NAME)"
