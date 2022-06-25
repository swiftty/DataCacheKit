import Foundation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class ManualClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol {
        var offset: Duration = .zero

        public func advanced(by duration: Duration) -> ManualClock.Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: ManualClock.Instant) -> Duration {
            other.offset - offset
        }

        public static func < (_ lhs: ManualClock.Instant, _ rhs: ManualClock.Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    struct WakeUp {
        var when: Instant
        var continuation: UnsafeContinuation<Void, Never>
    }

    public private(set) var now = Instant()

    public var minimumResolution: Duration = .zero

    // General storage for the sleep points we want to wake-up for
    // this could be optimized to be a more efficient data structure
    // as well as enforced for generation stability for ordering
    var wakeUps = [WakeUp]()

    // adjusting now or the wake-ups can be done from different threads/tasks
    // so they need to be treated as critical mutations
    let lock = os_unfair_lock_t.allocate(capacity: 1)

    deinit {
        lock.deallocate()
    }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        // Enqueue a pending wake-up into the list such that when
        return await withUnsafeContinuation {
            if deadline <= now {
                $0.resume()
            } else {
                os_unfair_lock_lock(lock)
                wakeUps.append(WakeUp(when: deadline, continuation: $0))
                os_unfair_lock_unlock(lock)
            }
        }
    }

    public func advance(by amount: Duration) {
        // step the now forward and gather all of the pending
        // wake-ups that are in need of execution
        os_unfair_lock_lock(lock)
        now = now.advanced(by: amount)
        var toService = [WakeUp]()
        for index in (0..<(wakeUps.count)).reversed() {
            let wakeUp = wakeUps[index]
            if wakeUp.when <= now {
                toService.insert(wakeUp, at: 0)
                wakeUps.remove(at: index)
            }
        }
        os_unfair_lock_unlock(lock)

        // make sure to service them outside of the lock
        toService.sort { lhs, rhs -> Bool in
            lhs.when < rhs.when
        }
        for item in toService {
            item.continuation.resume()
        }
    }
}
