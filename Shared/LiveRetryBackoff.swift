import Foundation

// Bound automatic retries while a recording is active. Manual reconnect or a working audio
// acknowledgement resets the budget; denied permissions must not cause an endless retry loop.
struct LiveRetryBackoff {
    private var attempt = 0
    private let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    mutating func nextDelay() -> TimeInterval? {
        guard attempt < delays.count else { return nil }
        defer { attempt += 1 }
        return delays[attempt]
    }

    mutating func reset() { attempt = 0 }
}
