import Foundation
import OSLog

public final class MemoryCache<Key: Hashable & Sendable, Value: Sendable>: Caching, @unchecked Sendable {
    public let options: Options
    public let logger: Logger

    private let nsCache = NSCache<KeyWrapper<Key>, ValueWrapper<Value>>()
    private let queueingLock = NSLock()
    private var queueingTask: Task<Void, Never>?

    public subscript (key: Key) -> Value? {
        get async {
            await value(for: key)
        }
    }

    public init(options: Options, logger: Logger = .init(.disabled)) {
        self.options = options
        self.logger = logger
        nsCache.countLimit = options.countLimit
        if let costLimit = options.costLimit {
            nsCache.totalCostLimit = costLimit
        }
    }

    public func value(for key: Key) async -> Value? {
        _ = await queueingTask?.result
        return nsCache.object(forKey: .init(key))?.value
    }

    @discardableResult
    public func store(_ value: Value, for key: Key) -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            nsCache.setObject(.init(value), forKey: .init(key), cost: (value as? Data)?.count ?? 0)
        }
        queueingTask = task
        return task
    }

    @discardableResult
    public func remove(for key: Key) -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            nsCache.removeObject(forKey: .init(key))
        }
        queueingTask = task
        return task
    }

    @discardableResult
    public func removeAll() -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            nsCache.removeAllObjects()
        }
        queueingTask = task
        return task
    }
}

// MARK: -
private final class KeyWrapper<Key: Hashable & Sendable>: Hashable {
    let key: Key

    init(_ key: Key) { self.key = key }

    static func == (lhs: KeyWrapper, rhs: KeyWrapper) -> Bool {
        lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

private final class ValueWrapper<Value> {
    let value: Value

    init(_ value: Value) { self.value = value }
}
