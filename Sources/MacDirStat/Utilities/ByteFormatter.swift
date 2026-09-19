import Foundation
import os

enum ByteFormatter {
    // ByteCountFormatter is not documented as thread-safe, and this is read
    // from the render pass, status bar, and detail panel. Guard the shared
    // instance with a lock so concurrent access can't race.
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    private static let lock = OSAllocatedUnfairLock()

    static func string(from bytes: Int64) -> String {
        lock.withLock { formatter.string(fromByteCount: bytes) }
    }

    static func string(from bytes: UInt64) -> String {
        lock.withLock { formatter.string(fromByteCount: Int64(clamping: bytes)) }
    }
}
