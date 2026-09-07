import os

enum FlowLog {
    static let subsystem = "net.ai2048.flowbox"

    static let screenshot = Logger(subsystem: subsystem, category: "screenshot")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let scroll = Logger(subsystem: subsystem, category: "scroll")
    static let permission = Logger(subsystem: subsystem, category: "permission")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let general = Logger(subsystem: subsystem, category: "general")

    static func logError(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func logInfo(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func logDebug(_ logger: Logger, _ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
