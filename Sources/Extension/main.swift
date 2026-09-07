import Foundation

// appex 的入口:运行扩展主运行循环,加载 Info.plist 里
// NSExtensionPrincipalClass 指向的 FinderSync 类。
// Xcode 模板通过链接器入口点(LD_ENTRY_POINT)隐式完成同一件事;
// SPM 构建必须显式调用。符号由 Foundation 在 dyld 共享缓存中提供。
@_silgen_name("NSExtensionMain")
func NSExtensionMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

_ = NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
