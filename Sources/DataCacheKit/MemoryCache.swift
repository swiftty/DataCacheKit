import Foundation
import OSLog

public actor MemoryCache<Key: Hashable & Sendable, Value: Sendable>: Caching {
    public nonisolated let options: Options
    public nonisolated let logger: Logger

    private let lruCache = LRUCache<Key, Value>()
    private var queueingTask: Task<Void, Never>?

    public subscript (key: Key) -> Value? {
        get async {
            await value(for: key)
        }
    }

    public init(options: Options, logger: Logger = .init(.disabled)) {
        self.options = options
        self.logger = logger
        lruCache.countLimit = options.countLimit
        if let costLimit = options.sizeLimit {
            lruCache.totalCostLimit = costLimit
        }
    }

    public func value(for key: Key) async -> Value? {
        _ = await queueingTask?.result
        return lruCache.value(forKey: key)
    }

    @discardableResult
    public func store(_ value: Value, for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            lruCache.setValue(value, forKey: key, cost: (value as? Data)?.count ?? 0)
        }
    }

    @discardableResult
    public func remove(for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            lruCache.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func removeAll() -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            lruCache.removeAllValues()
        }
    }
}
