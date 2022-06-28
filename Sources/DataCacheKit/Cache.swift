import Foundation
import OSLog

public final class Cache<Key: Hashable & Sendable, Value: Codable & Sendable>: Caching, @unchecked Sendable {
    public typealias Options = (forMemory: MemoryCache<Key, Value>.Options, forDisk: DiskCache<Key>.Options)

    public let options: Options
    public let logger: Logger

    public subscript (key: Key) -> Value? {
        get async throws {
            try await value(for: key)
        }
    }

    private let onMemery: MemoryCache<Key, Value>
    private let onDisk: DiskCache<Key>

    private let queueingLock = NSLock()
    private var queueingTask: Task<Void, Never>?

    public init(options: Options, logger: Logger = .init(.disabled)) {
        self.onMemery = .init(options: options.forMemory, logger: logger)
        self.onDisk = .init(options: options.forDisk, logger: logger)
        self.options = options
        self.logger = logger
    }

    public func prepare() throws {
        try onDisk.prepare()
    }

    public func value(for key: Key) async throws -> Value? {
        _ = await queueingTask?.result

        if let value = await onMemery.value(for: key) {
            return value
        }

        guard let data = try await onDisk.value(for: key) else { return nil }

        let value: Value = try {
            if let v = data as? Value { return v }

            let decoder = JSONDecoder()
            return try decoder.decode(Value.self, from: data)
        }()

        onMemery.store(value, for: key)
        return value
    }

    @discardableResult
    public func store(_ value: Value, for key: Key) -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            async let memory: Void = await onMemery.store(value, for: key).value
            async let disk: Void = await _storeToDisk(value, for: key)

            await memory
            await disk
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
            async let memory: Void = await onMemery.remove(for: key).value
            async let disk: Void = await onDisk.remove(for: key).value

            await memory
            await disk
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

            async let memory: Void = await onMemery.removeAll().value
            async let disk: Void = await onDisk.removeAll().value

            await memory
            await disk
        }
        queueingTask = task
        return task
    }

    public func url(for key: Key) -> URL? {
        onDisk.url(for: key)
    }
}

extension Cache {
    func _storeToDisk(_ value: Value, for key: Key) async {
        if let data = value as? Data {
            await onDisk.store(data, for: key).value
        } else {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(value)
                await onDisk.store(data, for: key).value
            } catch {
                logger.error("\(String(describing: error))")
            }
        }
    }
}
