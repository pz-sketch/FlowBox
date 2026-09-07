#!/bin/bash
# 构建「FlowBox」:编译 → 组装 .app(含 Finder 扩展)→ ad-hoc 签名 → 安装 → 启动
# 仅需 Xcode Command Line Tools,无需完整 Xcode,也无需开发者账号。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="FlowBox"
EXT_NAME="FlowBoxExt"
BUNDLE_ID="net.ai2048.flowbox"
EXT_BUNDLE_ID="${BUNDLE_ID}.ext"
VERSION="1.0.0"

echo "==> 编译(release)..."
swift build -c release
BIN=".build/release"

echo "==> 组装 App 包..."
STAGING_DIR="$(mktemp -d)"
APP_ROOT="${STAGING_DIR}/${APP_NAME}.app"
EXT_ROOT="${APP_ROOT}/Contents/PlugIns/${EXT_NAME}.appex"
mkdir -p "${APP_ROOT}/Contents/MacOS" "${EXT_ROOT}/Contents/MacOS"

cp "${BIN}/${APP_NAME}" "${APP_ROOT}/Contents/MacOS/${APP_NAME}"
mkdir -p "${APP_ROOT}/Contents/Resources"
if [ -f "Resources/AppIcon.icns" ]; then cp "Resources/AppIcon.icns" "${APP_ROOT}/Contents/Resources/AppIcon.icns"; fi
cp "${BIN}/${EXT_NAME}" "${EXT_ROOT}/Contents/MacOS/${EXT_NAME}"

cat > "${APP_ROOT}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>极简工具箱</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>录屏时采集麦克风声音</string>
		<key>NSCameraUsageDescription</key>
		<string>人脸看守在本地检测是否有人(画面只进内存,不保存不上传);录屏时可在画面上叠加摄像头画中画</string>
	<key>NSScreenCaptureDescription</key>
	<string>录屏/截图时采集屏幕画面与系统声音</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>${BUNDLE_ID}</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>flowbox</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
EOF

cat > "${EXT_ROOT}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>极简工具箱</string>
	<key>CFBundleExecutable</key>
	<string>${EXT_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${EXT_BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${EXT_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.FinderSync</string>
		<key>NSExtensionPrincipalClass</key>
		<string>${EXT_NAME}.FinderSync</string>
	</dict>
</dict>
</plist>
EOF

echo "==> 签名(优先使用固定开发证书,签名稳定、系统授权不因重建失效)..."
# macOS 13+ 要求扩展必须沙盒化,否则 PlugInKit 拒绝收录;
# automation.apple-events 允许沙盒内的扩展通过 AppleScript 控制 Terminal
cat > "${STAGING_DIR}/Ext.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
EOF
SIGN_IDENTITY="FlowBoxDeveloper"
if security find-identity 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
    echo "   使用固定开发证书: ${SIGN_IDENTITY}"
    SIGNER="${SIGN_IDENTITY}"
elif security find-certificate -c "${SIGN_IDENTITY}" >/dev/null 2>&1; then
    echo "   使用固定开发证书: ${SIGN_IDENTITY} (证书)"
    SIGNER="${SIGN_IDENTITY}"
else
    echo "   未找到开发证书,回退 ad-hoc 签名"
    SIGNER="-"
fi
codesign --force --sign "${SIGNER}" --entitlements "${STAGING_DIR}/Ext.entitlements" "${EXT_ROOT}"
codesign --force --sign "${SIGNER}" "${APP_ROOT}"
rm -rf /tmp/flowbox-sign-test.app

echo "==> 停止旧版本并安装..."
killall "${APP_NAME}" 2>/dev/null || true
# 等旧实例完全退出,避免新实例被单实例保护误判退出
sleep 1

DEST_DIR="/Applications"
if [ ! -w "${DEST_DIR}" ]; then
    DEST_DIR="${HOME}/Applications"
    mkdir -p "${DEST_DIR}"
fi
rm -rf "${DEST_DIR}/${APP_NAME}.app"
cp -R "${APP_ROOT}" "${DEST_DIR}/${APP_NAME}.app"

echo "==> 启动..."
open "${DEST_DIR}/${APP_NAME}.app"

echo ""
echo "✅ 安装完成:${DEST_DIR}/${APP_NAME}.app"
echo "   下一步:点击菜单栏图标 →「启用扩展」,在系统设置中打开「FlowBox」开关。"
echo ""
echo "扩展注册状态:"
pluginkit -m -p com.apple.FinderSync 2>/dev/null | grep -i "flowbox" \
    || echo "(系统尚未列出该扩展,完成系统设置里的勾选后生效;必要时重启 Finder)"
