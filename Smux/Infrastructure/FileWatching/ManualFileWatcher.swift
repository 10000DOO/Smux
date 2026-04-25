import Foundation

nonisolated final class ManualFileWatcher: FileWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var activeScopes: Set<FileWatchScope> = []
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

    func startWatching(_ scope: FileWatchScope) {
        locked {
            _ = activeScopes.insert(scope)
        }
    }

    func stopWatching(_ scope: FileWatchScope) {
        locked {
            _ = activeScopes.remove(scope)
        }
    }

    func stopAll() {
        locked {
            activeScopes.removeAll()
        }
    }

    func emit(_ event: FileWatchEvent) {
        emit([event])
    }

    func emit(_ events: [FileWatchEvent]) {
        let delivery = locked {
            let deliverableEvents = events.filter { activeScopes.contains($0.scope) }
            return (deliverableEvents, lockedEventHandler)
        }

        guard !delivery.0.isEmpty else {
            return
        }

        delivery.1?(delivery.0)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
