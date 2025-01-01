import Foundation
import OSLog

public actor MemoryCache<Key: Hashable & Sendable, Value: Sendable>: Caching {
    public nonisolated let options: Options
    public nonisolated let logger: Logger

    private let nsCache = NSCache<KeyWrapper<Key>, ValueWrapper<Value>>()
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
        if let costLimit = options.sizeLimit {
            nsCache.totalCostLimit = costLimit
        }
    }

    public func value(for key: Key) async -> Value? {
        _ = await queueingTask?.result
        return nsCache.object(forKey: .init(key))?.value
    }

    @discardableResult
    public func store(_ value: Value, for key: Key) -> Task<Void, Never> {
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
private final class KeyWrapper<Key: Hashable & Sendable>: NSObject {
    let key: Key

    init(_ key: Key) { self.key = key }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? KeyWrapper<Key> else { return false }
        return key == other.key
    }

    override var hash: Int {
        key.hashValue
    }
}

private final class ValueWrapper<Value> {
    let value: Value

    init(_ value: Value) { self.value = value }
}
