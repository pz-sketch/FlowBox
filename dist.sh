#!/bin/bash
# 打包分发用 DMG:编译 → 组装 .app(固定证书签名)→ 生成可分发磁盘映像
# 用法:./dist.sh    产物:dist/FlowBox.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="FlowBox"
EXT_NAME="FlowBoxExt"
BUNDLE_ID="net.ai2048.flowbox"
EXT_BUNDLE_ID="${BUNDLE_ID}.ext"
VERSION="1.0.2"
DIST_DIR="dist"

echo "==> 编译(release)..."
swift build -c release
BIN=".build/release"

echo "==> 组装 App 包..."
STAGING_DIR="$(mktemp -d)"
APP_ROOT="${STAGING_DIR}/${APP_NAME}.app"
EXT_ROOT="${APP_ROOT}/Contents/PlugIns/${EXT_NAME}.appex"
mkdir -p "${APP_ROOT}/Contents/MacOS" "${EXT_ROOT}/Contents/MacOS"

cp "${BIN}/${APP_NAME}" "${APP_ROOT}/Contents/MacOS/${APP_NAME}"
cp "${BIN}/${EXT_NAME}" "${EXT_ROOT}/Contents/MacOS/${EXT_NAME}"

cat > "${APP_ROOT}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>FlowBox</string>
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
	<string>FlowBox</string>
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

echo "==> 签名..."
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
    SIGNER="${SIGN_IDENTITY}"
elif security find-certificate -c "${SIGN_IDENTITY}" >/dev/null 2>&1; then
    SIGNER="${SIGN_IDENTITY}"
else
    SIGNER="-"
fi
echo "   使用签名身份: ${SIGNER}"
codesign --force --sign "${SIGNER}" --entitlements "${STAGING_DIR}/Ext.entitlements" "${EXT_ROOT}"
codesign --force --sign "${SIGNER}" "${APP_ROOT}"

echo "==> 组装 DMG 内容目录..."
CONTENT_DIR="${STAGING_DIR}/dmg"
mkdir -p "${CONTENT_DIR}"
cp -R "${APP_ROOT}" "${CONTENT_DIR}/"
ln -s /Applications "${CONTENT_DIR}/Applications"

cat > "${CONTENT_DIR}/安装说明.txt" <<'EOF'
极简工具箱 — 首次安装步骤
========================

1. 把「极简工具箱.app」拖进旁边的「Applications」文件夹

2. 首次打开(重要):
   在「应用程序」里 右键点击 FlowBox → 选「打开」→ 再点「打开」。
   直接双击会提示无法验证开发者,这是没有 99 美元开发者账号的正常现象,
   右键打开只需做一次。

3. 启用 Finder 右键菜单:
   点屏幕右上角菜单栏的「FlowBox」图标 →「启用扩展(打开系统设置)」,
   打开「FlowBox」的开关;
   如果列表里找不到,在终端执行:
       pluginkit -e use -i net.ai2048.flowbox.ext
   然后重启 Finder(pkill Finder)即可。

4. 如需「反转鼠标滚轮 / 流畅滚动」功能:
   设置 → 鼠标 里打开对应开关,系统会要求授予「辅助功能」权限,
   按提示允许后回来重新打开开关(每台电脑都要做一次)。

5. 自定义新建文件模板:
   菜单栏图标 → 设置…,改动即时生效。

适用于较新的 macOS(Apple Silicon / Intel 通用);
遇到安全提示一律选「仍要打开/允许」。
卸载:退出应用 → 删除 App 与 ~/Library/Containers/net.ai2048.flowbox.ext
EOF

mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${APP_NAME}.dmg"
echo "==> 生成 DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${CONTENT_DIR}" \
    -ov -format UDZO \
    "${DIST_DIR}/${APP_NAME}.dmg" | tail -1

echo ""
echo "✅ 分发包已生成: ${DIST_DIR}/${APP_NAME}.dmg ($(du -h "${DIST_DIR}/${APP_NAME}.dmg" | cut -f1 | tr -d ' '))"
