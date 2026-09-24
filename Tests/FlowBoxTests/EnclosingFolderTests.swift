import Testing
import SharedCore
import Foundation

@Suite("EnclosingFolder")
struct EnclosingFolderTests {

    /// `targetedURL` 始终是窗口正在浏览的目录(实机验证:在文件上右键它返回该文件所在目录),
    /// 所以「进入上级目录」就是取它的父目录。曾经按「项目上右键要往上游两层」实现,
    /// 实机一测会一次跳两层 —— 这个用例把正确语义钉住。
    @Test
    func destinationIsParentOfBrowsedDirectory() {
        let proj = URL(fileURLWithPath: "/Users/someone/work/proj", isDirectory: true)
        #expect(EnclosingFolder.destination(target: proj)?.path == "/Users/someone/work")
    }

    @Test
    func fileTargetResolvesAgainstItsOwnDirectory() {
        let file = URL(fileURLWithPath: "/Users/someone/work/proj/a.txt")
        #expect(EnclosingFolder.destination(target: file)?.path == "/Users/someone/work/proj")
    }

    @Test
    func noTargetYieldsNoDestination() {
        #expect(EnclosingFolder.destination(target: nil) == nil)
    }

    /// 根目录的父目录不是一个正常绝对路径(`deletingLastPathComponent` 返回 "/.."),
    /// 要返回 nil 而不是做无效跳转
    @Test
    func rootHasNoParent() {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        #expect(EnclosingFolder.parent(of: root) == nil)
        #expect(EnclosingFolder.destination(target: root) == nil)
    }

    @Test
    func normalDirectoryHasParent() {
        let proj = URL(fileURLWithPath: "/Users/someone/work/proj", isDirectory: true)
        #expect(EnclosingFolder.parent(of: proj)?.path == "/Users/someone/work")
    }

    /// 挂载卷的根目录有上级,不该被根判断误伤
    @Test
    func volumeRootStillHasParent() {
        let volume = URL(fileURLWithPath: "/Volumes/X", isDirectory: true)
        #expect(EnclosingFolder.parent(of: volume)?.path == "/Volumes")
    }
}
