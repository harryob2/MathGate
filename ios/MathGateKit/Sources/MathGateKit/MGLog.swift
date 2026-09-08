import Foundation
import os

/// Logging that is safe to leave switched on.
///
/// Hard rule, same as the Android side: never log the password or the `session` / `session.sig`
/// values. Status codes, redirect targets and cookie *names* only. Everything is interpolated as
/// `public` deliberately, so only pass strings that are already safe.
public enum MGLog {
    private static let logger = Logger(subsystem: "com.harryobrien.mathgate", category: "gate")

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
