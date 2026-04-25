import Foundation

nonisolated final class FileWatchDebouncer: @unchecked Sendable {
    private let interval: DispatchTimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingEvents: [FileWatchScope: FileWatchEvent] = [:]
    private var pendingScopes: [FileWatchScope] = []
    private var scheduledWorkItem: DispatchWorkItem?
    private var lockedEventHandler: (@Sendable ([FileWatchEvent]) -> Void)?

    var eventHandler: (@Sendable ([FileWatchEvent]) -> Void)? {
        get {
            locked {
                lockedEventHandler
            }
        }
        set {
            locked {
                lockedEventHandler = newValue
            }
        }
    }

    init(
        interval: TimeInterval = 0.25,
        queue: DispatchQueue = DispatchQueue(label: "Smux.FileWatchDebouncer")
    ) {
        self.interval = Self.dispatchInterval(for: interval)
        self.queue = queue
    }

    func submit(_ event: FileWatchEvent) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }

        locked {
            if pendingEvents[event.scope] == nil {
                pendingScopes.append(event.scope)
            }
            pendingEvents[event.scope] = event
            scheduledWorkItem?.cancel()
            scheduledWorkItem = workItem
        }

        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    func flush() {
        let flushState = locked {
            let events = pendingScopes.compactMap { pendingEvents[$0] }
            pendingEvents.removeAll()
            pendingScopes.removeAll()
            scheduledWorkItem?.cancel()
            scheduledWorkItem = nil
            return (events, lockedEventHandler)
        }

        guard !flushState.0.isEmpty else {
            return
        }

        flushState.1?(flushState.0)
    }

    func cancel() {
        locked {
            scheduledWorkItem?.cancel()
            scheduledWorkItem = nil
            pendingEvents.removeAll()
            pendingScopes.removeAll()
        }
    }

    func cancel(scope: FileWatchScope) {
        locked {
            pendingEvents.removeValue(forKey: scope)
            pendingScopes.removeAll { $0 == scope }
            if pendingEvents.isEmpty {
                scheduledWorkItem?.cancel()
                scheduledWorkItem = nil
            }
        }
    }

    private static func dispatchInterval(for interval: TimeInterval) -> DispatchTimeInterval {
        let nanoseconds = max(0, interval) * 1_000_000_000

        guard nanoseconds < Double(Int.max) else {
            return .nanoseconds(Int.max)
        }

        return .nanoseconds(Int(nanoseconds))
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
