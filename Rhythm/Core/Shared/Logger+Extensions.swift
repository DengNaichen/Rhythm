import Foundation
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "NaichengDeng.Rhythm"

    static let server = Logger(subsystem: subsystem, category: "server")

    static func service(_ name: String) -> Logger {
        Logger(subsystem: subsystem, category: "service.\(name)")
    }
}
