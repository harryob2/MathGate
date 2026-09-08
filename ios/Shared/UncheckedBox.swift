import Foundation

/// Carries a value the Apple SDKs hand us that Swift 6 cannot prove is `Sendable` — a
/// completion block, a `BGAppRefreshTask` — into a `Task`.
///
/// Only used where the value is handed to exactly one task and touched from nowhere else.
/// It is a deliberate, narrow escape hatch, not a general-purpose wrapper.
final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}
