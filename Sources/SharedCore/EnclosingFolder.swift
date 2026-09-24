import Foundation

/// 「进入上级目录」的落点计算。
///
/// 放在 SharedCore 是为了能被断言测试直接覆盖(不依赖 FinderSync 框架)。
///
/// 结论来自实机验证(扩展把 menuKind/targetedURL/选区写进宿主日志观察):
/// `targetedURL` **始终是窗口正在浏览的目录**,与右键位置无关 ——
/// 在文件上右键时它返回该文件所在目录、在文件夹上右键时返回该文件夹所在的目录、
/// 在窗口空白处右键时返回该目录本身。选区只是「点了哪个项目」,不参与定位。
///
/// 所以「进入上级目录」就是它的父目录,不需要按菜单种类分支:
/// 早期版本按「项目上右键要取两层」处理,结果一次跳两层;而拿选区当锚点也不可靠 ——
/// 右键空白处时 Finder 常保留着上次的选中项,同样会多跳一层。
public enum EnclosingFolder {

    /// 从窗口浏览的目录算出上级目录;已在根目录时返回 nil(不做无效跳转)
    public static func parent(of directory: URL) -> URL? {
        // 不能用「父目录 == 自己」来判断到顶:`deletingLastPathComponent()` 对根目录
        // 返回的是字面量 `/..`(本机实测),既不是空串也不等于 `/`,于是根目录会被
        // 当成有上级、跳到一个不存在的路径。这里按「已到 `/` 或结果不是正常绝对路径」判顶。
        let standardized = directory.standardizedFileURL
        guard standardized.path != "/" else { return nil }
        let path = standardized.deletingLastPathComponent().standardizedFileURL.path
        guard path != standardized.path, path.hasPrefix("/"), path != "/.." else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 右键目标(= 窗口浏览的目录)的上级目录
    public static func destination(target: URL?) -> URL? {
        guard let target = target else { return nil }
        return parent(of: target)
    }
}
