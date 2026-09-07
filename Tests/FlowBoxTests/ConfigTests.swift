import Testing
import SharedCore
import Foundation

@Suite("Config")
struct ConfigTests {

    @Test
    func defaultAppConfig() {
        let cfg = AppConfig.defaultConfig()
        #expect(cfg.menu.copyFolder == true)
        #expect(cfg.newFiles.count >= 1)
        #expect(abs(cfg.scroll.minStep - 60) < 0.01)
        #expect(abs(cfg.screenshot.penWidth - 4) < 0.01)
        #expect(cfg.recording.frameRate == 30)
        #expect(cfg.presence.enabled == false)
        #expect(abs(cfg.presence.lockAfterSeconds - 8) < 0.01)
        #expect(abs(cfg.presence.confirmAfterSeconds - 60) < 0.01)
        #expect(abs(cfg.presence.gracePeriod - 15) < 0.01)
        #expect(cfg.presence.saveCaptureOnLock == true)
    }

    @Test
    func appConfigCodableRoundtrip() throws {
        var cfg = AppConfig.defaultConfig()
        cfg.menu.copyFolder = false
        cfg.scroll.smoothScrolling = true
        cfg.scroll.minStep = 120
        cfg.screenshot.penColorHex = "#00FF00"
        cfg.recording.captureCamera = true
        cfg.recording.cameraWidth = 260
        cfg.presence.enabled = true
        cfg.presence.lockAfterSeconds = 12
        cfg.presence.confirmAfterSeconds = 90
        cfg.presence.gracePeriod = 20
        cfg.presence.saveCaptureOnLock = false
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.scroll.minStep == 120)
        #expect(decoded.screenshot.penColorHex == "#00FF00")
        #expect(decoded.recording.captureCamera == true)
        #expect(decoded.recording.cameraWidth == 260)
        #expect(decoded.presence.enabled == true)
        #expect(abs(decoded.presence.lockAfterSeconds - 12) < 0.01)
        #expect(abs(decoded.presence.confirmAfterSeconds - 90) < 0.01)
        #expect(abs(decoded.presence.gracePeriod - 20) < 0.01)
        #expect(decoded.presence.saveCaptureOnLock == false)
    }

    @Test
    func configBackwardCompatibility() throws {
        let json = #"{"menu":{"copyFolder":true},"scroll":{}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        #expect(decoded.menu.copyFolder == true)
        #expect(decoded.scroll.minStep == 60)
        #expect(decoded.scroll.smoothScrolling == false)
        #expect(decoded.presence.enabled == false)
    }

    @Test
    func newFileItemBase64() {
        let item = NewFileItem(name: "X", filename: "x.docx", content: "aaa", encoding: "base64")
        #expect(item.isBase64 == true)
        let item2 = NewFileItem(name: "Y", filename: "y.txt", content: "hello")
        #expect(item2.isBase64 == false)
    }

    @Test
    func newFileItemEquatable() {
        let a = NewFileItem(name: "A", filename: "a.md", content: "# hi")
        let b = NewFileItem(name: "A", filename: "a.md", content: "# hi")
        #expect(a == b)
    }

    @Test
    func screenshotDefaults() {
        let c = ScreenshotConfig()
        #expect(c.hotKeyCode == 0)
        #expect(c.hotKeyModifiers == 2048)
        #expect(c.penColorHex == "#FF3B30")
        #expect(c.mosaicBlock == 16)
    }

    @Test
    func recordingDefaults() {
        let c = RecordingConfig()
        #expect(c.hotKeyCode == 15)
        #expect(c.captureSystemAudio == true)
        #expect(c.captureMicrophone == true)
        #expect(c.captureCamera == false)
        #expect(c.cameraWidth == 220)
        #expect(c.cameraX == -1)
        #expect(c.cameraIsCircle == true)
    }

    @Test
    func scrollClamping() {
        var c = ScrollConfig()
        c.minStep = 500
        #expect(min(120, max(10, c.minStep)) == 120)
        c.minStep = 2
        #expect(min(120, max(10, c.minStep)) == 10)
    }

    @Test
    func rcCommandURLs() {
        let copy = RCCommand.copy(text: "hello world")
        #expect(copy != nil)
        #expect(copy?.scheme == "flowbox")
        #expect(copy?.host == "copy")
        #expect(RCCommand.terminal(dir: "/tmp")?.host == "terminal")
        #expect(RCCommand.newFile(dir: "/tmp", index: 0)?.host == "newfile")
        #expect(RCCommand.stripQuarantine(paths: ["/a","/b"]) != nil)
        #expect(RCCommand.stripQuarantine(paths: []) == nil)
    }

    @Test
    func configStoreURL() {
        let url = ConfigStore.configURL
        #expect(url.path.contains("Library/Containers"))
        #expect(url.path.contains("net.ai2048.flowbox.ext"))
        #expect(url.path.hasSuffix("config.json"))
    }
}
