# FlowBox

<p align="center">
  <strong>A native macOS toolbox for Finder, screenshots, recording, mouse wheels, and menu bar workflows.</strong><br/>
  一个原生 macOS 工具箱，帮你更快完成 Finder、截图、录屏、滚轮和菜单栏操作。
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/built%20with-Swift%205.10-orange" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/distribution-source%20build-blue" alt="Source build" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" />
</p>

> **Current status / 当前状态:** FlowBox is under active development. A signed and notarized public release and pricing will be announced separately. / FlowBox 正在持续开发中；签名公证的公开版本和价格将另行公布。

> 🌐 **Website / 官网:** [ai2048.net/flowbox](https://ai2048.net/flowbox/)

---

## English

FlowBox brings several high-frequency macOS workflows into one menu bar app: Finder context actions, annotated screenshots, screen recording, camera picture-in-picture, external mouse wheel controls, and menu bar overflow handling.

It is built with Swift and Apple-native frameworks rather than Electron. It is designed for people who want fewer app switches, local-first processing, and a native macOS experience.

### Why FlowBox

- **One entry point:** Finder, input, and creation tools live behind one menu bar icon.
- **Native by design:** Uses Finder Sync, ScreenCaptureKit, AVFoundation, Core Graphics, and other system APIs.
- **Configurable:** Change hotkeys, capture tools, recording options, mouse behavior, and new-file templates.
- **Local-first:** The current source contains no network upload, telemetry, or third-party analytics SDK; screenshots, recordings, and configuration are primarily handled on-device.
- **Developer-friendly:** Build with SwiftPM and Xcode Command Line Tools; a full Xcode installation is not required.

### Features

| Module | What it does |
| --- | --- |
| **Finder context menu** | Copy folder or selection paths, open the current folder in Terminal, and create files from templates. |
| **Screenshot & annotation** | Freeze the screen, select an area, then use pen, mosaic, text, rectangle, ellipse, and undo; copy PNG or save it to the Desktop. |
| **Screen recording** | Record the main display to `.mov`, with optional system audio, microphone, and camera PiP. |
| **Recording → GIF** | Convert a recording (or any mov/mp4) to an animated GIF via menu bar → Recording → GIF…, with adjustable frame rate and width; runs fully on-device. |
| **Camera PiP** | Preview before recording; drag it into position and configure circle/rectangle shape, size, mirroring, and position persistence. |
| **Mouse wheel controls** | Reverse external mouse wheel direction and smooth discrete wheel events while leaving trackpad events unchanged. |
| **Menu bar hider** | Put status icons pushed out by a notch or limited space into an expandable overflow menu. |
| **Quick actions** | Lock the screen, auto-lock when your face leaves or a stranger appears (on-device only, owner face enrolled locally), remove quarantine attributes from dropped files, and create files from configurable templates. |

### Hotkeys and workflow

- Screenshot default: `⌥A`
- Recording default: `⌥R`
- During capture: `Enter` copies, `Esc` cancels, `⌘Z` undoes, and `⌘S` saves a PNG
- Change hotkeys and feature options from the menu bar icon → **Settings…**

### Installation

#### Option A: Install a GitHub Release (recommended)

When a public Release is available, download the matching build from the repository’s **Releases** page and follow its signing, notarization, and first-launch notes.

> No public Release URL is configured yet. When publishing, replace this paragraph with: `[Download the latest release](your GitHub Release URL)`.

Unsigned, unnotarized, or ad-hoc test builds may trigger Gatekeeper warnings. Only download builds from sources you trust, and state the signing and notarization status on the release page.

#### Option B: Build from source

Requirements:

- macOS 13 or later
- Swift 5.10 toolchain
- Xcode Command Line Tools

```bash
git clone <your-repository-url>
cd flowBox
./build.sh
```

The script builds a Release configuration, assembles an `.app` containing the Finder extension, signs it, and installs it to `/Applications` (or `~/Applications` when needed).

Run tests:

```bash
swift test
```

Build a local DMG:

```bash
./dist.sh
```

`build.sh` and `dist.sh` prefer a local signing identity named `FlowBoxDeveloper` and otherwise fall back to ad-hoc signing. An ad-hoc build is intended for local development and testing, not as a cross-machine notarized distribution package.

### Enable the Finder extension once

1. Run `./build.sh` and launch FlowBox.
2. Click the FlowBox menu bar icon and choose **Enable Extension**.
3. Turn on the **FlowBox** Finder extension in System Settings.
   - macOS 13/14/15: Privacy & Security → Extensions
   - Newer systems: General → Login Items & Extensions
4. Return to Finder and check the context menu. If it is still missing:

```bash
killall Finder
```

### Permissions

FlowBox requests macOS permissions by feature; you do not need to grant every permission to use the basic app:

| Feature | Permission that may be required |
| --- | --- |
| Finder context menu | Finder Sync extension switch; opening Terminal may request Automation permission the first time. |
| Screenshots / screen recording | Screen Recording. |
| System audio capture | Screen Recording. |
| Microphone input | Microphone. |
| Camera PiP | Camera. |
| Face-away auto-lock | Camera (frames stay in memory for on-device face-rectangle detection; never saved or uploaded). |
| Stranger lock (optional) | Camera. Compares faces against a locally enrolled owner feature vector stored in your config; answers owner-or-not only, never identifies who. |
| Wheel reversal / smooth scrolling | Accessibility; some system configurations may also require Input Monitoring. |
| Menu bar hider | Screen Recording to resolve status-item names and icons. |
| Lock screen / quarantine removal | Apple Events or administrator authorization may be requested, depending on the system and action path. |

Permissions are controlled by macOS. FlowBox does not bypass system authorization; a denied permission leaves the related feature disabled or unavailable.

### Privacy and data handling

- The current source contains no network requests, file upload, telemetry, or third-party analytics SDK.
- Screenshots, recordings, templates, and configuration are primarily processed on-device.
- The app uses macOS system logging. Debug builds may also write `/tmp/flowbox-shot-debug.log` and `/tmp/flowbox-scroll-debug.log`; entries may include paths, dimensions, or input-event diagnostics.
- Configuration is stored at:

```text
~/Library/Containers/net.ai2048.flowbox.ext/Data/Library/Application Support/FlowBox/config.json
```

### FAQ

**FlowBox is missing from Finder’s context menu.**

Check that the Finder extension is enabled, then try `killall Finder`. A rebuilt development app may need to be re-authorized or re-enabled after its signature changes.

**The wheel feature does nothing.**

Enable it in Settings and allow FlowBox under System Settings → Privacy & Security → Accessibility. Rebuilding an ad-hoc app can change its identity and require authorization again.

**macOS says it cannot verify the developer.**

This usually means the app is not notarized. For a trusted build, use “right-click → Open”; production releases should clearly state their signing and notarization status.

**Can I move a local build to another Mac?**

A local ad-hoc build is not intended as a cross-machine installer. Cross-machine distribution should use a stable signing identity and Apple notarization; supported architectures should be confirmed in the Release artifacts.

### Uninstall

Quit FlowBox, remove the app and its container data, then disable the Finder extension in System Settings:

```bash
killall FlowBox 2>/dev/null || true
rm -rf /Applications/FlowBox.app
rm -rf ~/Applications/FlowBox.app
rm -rf ~/Library/Containers/net.ai2048.flowbox.ext
```

### Project structure

```text
Package.swift               SwiftPM package
Sources/SharedCore/         Host and extension shared configuration
Sources/App/                Menu bar host application
  main.swift                App delegate, menu, URL command executor
  HotKeyCenter.swift        Global hotkeys
  Screenshot.swift          Screenshot capture and annotation
  ScreenRecorder.swift      Screen recording and PiP compositing
  ScrollReverser.swift      Wheel reversal and smooth scrolling
  MenuBarHider.swift        Menu bar overflow handling
  SettingsWindow.swift      Settings UI
Sources/Extension/          Finder Sync extension
Tests/FlowBoxTests/         Logic and compositor tests
build.sh                    Build, sign, install, and launch
dist.sh                     Build and package a local DMG
```

### Technical architecture

- Menu bar host app + Finder Sync extension
- The extension delegates actions to the host through the `flowbox://` URL scheme
- Screenshots and recording use ScreenCaptureKit, AVFoundation, and native graphics APIs
- Camera picture-in-picture is composited into the local recording
- SwiftPM builds the targets; shell scripts assemble the `.app`, embed the extension, and sign it

### Releasing

The version lives in two places — `build.sh` and `dist.sh` — and both must agree.

```bash
# 1. bump VERSION in build.sh and dist.sh, then commit and push
# 2. tag it — CI builds, signs and publishes from there
git tag v1.0.2 && git push origin v1.0.2
```

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds the DMG,
verifies it carries the fixed `FlowBoxDeveloper` signature (an ad-hoc build fails
the run rather than shipping), and publishes a GitHub Release with the DMG attached.
Release notes are read from `.github/release-notes/<tag>.md` when that file exists.

Running the workflow manually (Actions → Release FlowBox → Run workflow) builds and
uploads the DMG as a workflow artifact **without** publishing a release — use that to
verify the signing chain on its own.

The workflow expects three repository secrets:

| Secret | Contents |
| --- | --- |
| `FLOWBOX_CERT_P12_BASE64` | base64 of the `FlowBoxDeveloper` certificate **with its private key**, exported as `.p12` |
| `FLOWBOX_P12_PASSWORD` | the passphrase that `.p12` was exported with |
| `FLOWBOX_KEYCHAIN_PASSWORD` | any throwaway string; unlocks the temporary keychain on the runner |

To re-export the certificate (it is self-signed and never trusted by the system, so
`find-identity -v` reports zero valid identities — that is expected):

```bash
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 -o /tmp/flowbox-sign.p12 -P '<passphrase>'
base64 -i /tmp/flowbox-sign.p12 | pbcopy   # paste into FLOWBOX_CERT_P12_BASE64
rm -f /tmp/flowbox-sign.p12                # do not leave the private key on disk
```

> The certificate must stay the same across releases. Rotating it changes the app's
> designated requirement, and macOS then treats the update as a different app and
> resets the permissions users had granted.


---

## 中文

FlowBox 把一组高频 macOS 操作放进一个轻量菜单栏应用：Finder 右键增强、截图标注、屏幕录制、摄像头画中画、外接鼠标滚轮增强，以及菜单栏图标收纳。

它使用 Swift 和 Apple 原生框架实现，不依赖 Electron。适合希望减少工具切换、重视本地处理、又想保留 macOS 原生体验的用户。

### 为什么选择 FlowBox

- **一个入口**：常用 Finder、输入和创作工具集中在菜单栏。
- **原生体验**：使用 Finder Sync、ScreenCaptureKit、AVFoundation、Core Graphics 等系统能力。
- **可配置**：快捷键、截图工具、录屏选项、鼠标行为和新建文件模板都可以调整。
- **本地优先**：当前源码未包含网络上传、遥测或第三方分析 SDK；截图、录屏和配置主要在本机处理。
- **对开发者友好**：可以只使用 Xcode Command Line Tools 和 SwiftPM 构建，不要求完整 Xcode。

### 功能一览

| 模块 | 能做什么 |
| --- | --- |
| **Finder 右键菜单** | 复制当前目录路径、复制所选文件路径、在 Terminal 中打开目录、从模板新建文件。 |
| **截图与标注** | 冻结屏幕、框选区域，拖动移动选区，使用画笔、马赛克、文字、矩形、椭圆和撤销；复制 PNG 或保存到桌面。 |
| **屏幕录制** | 录制主屏幕并保存为 `.mov`；可选系统声音、麦克风和摄像头画中画。 |
| **录屏转 GIF** | 把录屏（或任意 mov/mp4）转成动图 GIF：菜单栏 →「录屏转 GIF…」，可调帧率与最大宽度，全程本机处理；完成后直接弹出 Quick Look 播放动画（无需去 Finder 双击）。 |
| **摄像头画中画** | 录制前即可预览；支持拖动、圆形/矩形、尺寸、镜像和位置记忆。 |
| **鼠标滚轮增强** | 反转外接鼠标滚轮方向，并将离散滚轮事件转换为更连续的滚动；触控板事件保持不变。 |
| **菜单栏收纳** | 将被刘海或空间限制挤出的状态图标放入可展开的收纳菜单。 |
| **快捷操作** | 一键锁屏、人脸离开自动锁屏 / 陌生人脸锁屏(纯本地检测,主人脸需先在设置里注册)、拖入文件去除 quarantine 属性，以及可配置的新建文件模板。 |

### 快捷键与使用方式

- 截图默认快捷键：`⌥A`
- 录屏默认快捷键：`⌥R`
- 截图中：`Enter` 复制结果，`Esc` 取消，`⌘Z` 撤销，`⌘S` 保存 PNG；未选绘制工具时在选区内拖动可移动整个选区（选了工具后按住 `⌥` 拖动同样可移动）
- 所有快捷键和工具选项都可以在菜单栏图标 → **设置…** 中修改

### 安装方式

#### 方式 A：安装 GitHub Release（推荐）

正式 Release 发布后，请从本仓库的 **Releases** 页面下载对应版本，并按照 Release Notes 中的签名、公证和首次启动说明安装。

> 当前仓库尚未提供可直接填写的 Release 下载地址。发布时可将本段替换为：`[下载最新版](你的 GitHub Release URL)`。

未公证或使用 ad-hoc 签名的测试包可能触发 Gatekeeper 提示。请只从你信任的来源下载，并在发布页面明确标注签名与公证状态。

#### 方式 B：从源码构建

系统要求：

- macOS 13 或更高版本
- Swift 5.10 工具链
- Xcode Command Line Tools

```bash
git clone <your-repository-url>
cd flowBox
./build.sh
```

脚本会编译 Release 版本、组装包含 Finder 扩展的 `.app`、签名，并安装到 `/Applications`；若没有写入权限，则安装到 `~/Applications`。

运行测试：

```bash
swift test
```

生成本地 DMG：

```bash
./dist.sh
```

`build.sh` 和 `dist.sh` 会优先使用名为 `FlowBoxDeveloper` 的本地签名身份，否则回退到 ad-hoc 签名。ad-hoc 构建适合本机开发和测试，不等同于可跨机器分发的公证安装包。

### 首次启用 Finder 扩展

1. 运行 `./build.sh` 并启动 FlowBox。
2. 点击菜单栏中的 FlowBox 图标，选择 **启用扩展（打开系统设置）**。
3. 在系统设置中打开 **FlowBox** Finder 扩展开关。
   - macOS 13/14/15：隐私与安全性 → 扩展
   - 较新系统：通用 → 登录项与扩展
4. 回到 Finder 后右键检查菜单。若菜单仍未出现，可执行：

```bash
killall Finder
```

### 权限说明

FlowBox 按功能请求 macOS 权限，不同功能不需要全部授权：

| 功能 | 可能需要的权限 |
| --- | --- |
| Finder 右键菜单 | Finder Sync 扩展开关；“在终端中打开”首次使用可能需要自动化权限。 |
| 截图 / 屏幕录制 | 屏幕录制。 |
| 系统声音录制 | 屏幕录制。 |
| 麦克风画面 | 麦克风。 |
| 摄像头画中画 | 摄像头。 |
| 人脸离开自动锁屏 | 摄像头(画面只进内存做本地人脸矩形检测,不保存不上传)。 |
| 陌生人脸锁屏(可选) | 摄像头。与本机配置里注册的主人脸特征向量比对,只回答"是主人/不是主人",不识别具体是谁。 |
| 滚轮反转 / 流畅滚动 | 辅助功能；部分系统配置可能还需要输入监控。 |
| 菜单栏收纳 | 屏幕录制，用于读取状态项名称和图标。 |
| 一键锁屏 / 去除隔离属性 | 可能触发 Apple Events 或管理员授权，取决于系统环境和操作路径。 |

权限由 macOS 管理。FlowBox 不应绕过系统授权；如果拒绝权限，对应功能会保持关闭或不可用。

### 隐私与数据处理

- 当前源码中未发现网络请求、文件上传、遥测或第三方分析 SDK。
- 截图、录屏、模板和配置主要在本机处理。
- 应用会使用 macOS 系统日志；调试版本还可能写入 `/tmp/flowbox-shot-debug.log` 和 `/tmp/flowbox-scroll-debug.log`。日志内容可能包含路径、尺寸或输入事件诊断信息。
- 配置文件位于：

```text
~/Library/Containers/net.ai2048.flowbox.ext/Data/Library/Application Support/FlowBox/config.json
```

### 常见问题

**Finder 右键没有 FlowBox？**

检查 Finder 扩展开关是否打开，并尝试 `killall Finder`。开发构建重签后，系统可能要求重新授权或重新启用扩展。

**滚轮功能没有反应？**

在设置中开启对应功能，并在系统设置 → 隐私与安全性 → 辅助功能中允许 FlowBox。重建应用后，ad-hoc 签名变化可能导致 macOS 要求重新授权。

**首次打开提示无法验证开发者？**

这通常意味着应用未经过公证。仅对可信来源的构建包执行“右键 → 打开”，正式发布时应提供签名和公证状态说明。

**换一台 Mac 可以直接使用吗？**

本地 ad-hoc 构建不适合作为跨机器安装包。跨机器分发应使用稳定签名并完成 Apple 公证；具体支持的架构以 Release 产物说明为准。

### 卸载

退出 FlowBox 后删除应用和容器数据，然后在系统设置中关闭 Finder 扩展：

```bash
killall FlowBox 2>/dev/null || true
rm -rf /Applications/FlowBox.app
rm -rf ~/Applications/FlowBox.app
rm -rf ~/Library/Containers/net.ai2048.flowbox.ext
```

### 项目结构

```text
Package.swift               SwiftPM package
Sources/SharedCore/         Host and extension shared configuration
Sources/App/                Menu bar host application
  main.swift                App delegate, menu, URL command executor
  HotKeyCenter.swift        Global hotkeys
  Screenshot.swift          Screenshot capture and annotation
  ScreenRecorder.swift      Screen recording and PiP compositing
  ScrollReverser.swift      Wheel reversal and smooth scrolling
  MenuBarHider.swift        Menu bar overflow handling
  SettingsWindow.swift      Settings UI
Sources/Extension/          Finder Sync extension
Tests/FlowBoxTests/         Logic and compositor tests
build.sh                    Build, sign, install, and launch
dist.sh                     Build and package a local DMG
```

### 技术架构

- 菜单栏宿主应用 + Finder Sync Extension
- 扩展通过 `flowbox://` URL scheme 将动作交给宿主执行
- 截图和录屏分别使用 ScreenCaptureKit、AVFoundation 和系统图形能力
- 录屏中的摄像头画中画由本地视频合成
- SwiftPM 负责编译，脚本负责组装 `.app`、嵌入扩展和签名

### 发版流程

版本号写在**两个地方** —— `build.sh` 和 `dist.sh`，必须一致。

```bash
# 1. 改 build.sh / dist.sh 里的 VERSION，提交并推送
# 2. 打 tag 推上去，剩下的交给 CI
git tag v1.0.2 && git push origin v1.0.2
```

推送 `v*` tag 会触发 `.github/workflows/release.yml`：构建 DMG → 校验使用的是固定证书
`FlowBoxDeveloper` 签名（若是 ad-hoc 签名会**直接让这次运行失败**，不会把不合格的包发出去）
→ 创建 GitHub Release 并挂上 DMG。发布说明取自 `.github/release-notes/<tag>.md`（存在时）。

手动运行该工作流（Actions → Release FlowBox → Run workflow）只构建并上传 DMG 作为 workflow
artifact，**不发 release** —— 用它单独验证签名链路是否正常。

工作流依赖三个仓库 secrets：

| Secret | 内容 |
| --- | --- |
| `FLOWBOX_CERT_P12_BASE64` | `FlowBoxDeveloper` 证书**连同私钥**导出为 `.p12` 后的 base64 |
| `FLOWBOX_P12_PASSWORD` | 导出该 `.p12` 时设置的密码 |
| `FLOWBOX_KEYCHAIN_PASSWORD` | 任意临时字符串，用于解锁 runner 上的临时钥匙串 |

重新导出证书（它是自签名证书，系统从不信任它，所以 `find-identity -v` 显示 0 个有效身份，
这是正常的）：

```bash
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 -o /tmp/flowbox-sign.p12 -P '<密码>'
base64 -i /tmp/flowbox-sign.p12 | pbcopy   # 粘贴进 FLOWBOX_CERT_P12_BASE64
rm -f /tmp/flowbox-sign.p12                # 别把私钥留在磁盘上
```

> 证书必须**保持同一把**。换证书会改变应用的指定要求（designated requirement），macOS 会把
> 新版本当成另一个应用，用户之前授予的权限会被重置。

---

## License

FlowBox is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 pz-sketch.

The MIT License applies to this repository’s code. Third-party dependencies, assets, and Apple system services remain subject to their respective terms.
