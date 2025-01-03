import Foundation
import OSLog

public actor Cache<Key: Hashable & Sendable, Value: Codable & Sendable>: Caching {
    public struct Options: Sendable {
        public let forMemory: MemoryCache<Key, Value>.Options
        public let forDisk: DiskCache<Key>.Options

        public init(forMemory: MemoryCache<Key, Value>.Options, forDisk: DiskCache<Key>.Options) {
            self.forMemory = forMemory
            self.forDisk = forDisk
        }
    }

    public nonisolated let options: Options
    public nonisolated let logger: Logger

    public subscript (key: Key) -> Value? {
        get async throws {
            try await value(for: key)
        }
    }

    private let onMemery: MemoryCache<Key, Value>
    private let onDisk: DiskCache<Key>

    private var queueingTask: Task<Void, Never>?

    public init(options: Options, logger: Logger = .init(.disabled)) {
        self.onMemery = .init(options: options.forMemory, logger: logger)
        self.onDisk = .init(options: options.forDisk, logger: logger)
        self.options = options
        self.logger = logger
    }

    public func prepare() async throws {
        try await onDisk.prepare()
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

        await onMemery.store(value, for: key).value
        return value
    }

    @discardableResult
    public nonisolated func store(_ value: Value, for key: Key) -> Task<Void, Never> {
        return Task {
            let task = await _store(value, for: key)
            await task.value
        }
    }

    private func _store(_ value: Value, for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            async let memory: Void = await onMemery.store(value, for: key).value
            async let disk: Void = await _storeToDisk(value, for: key)

            await memory
            await disk
        }
    }

    @discardableResult
    public nonisolated func remove(for key: Key) -> Task<Void, Never> {
        return Task {
            let task = await _remove(for: key)
            await task.value
        }
    }

    private func _remove(for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            async let memory: Void = await onMemery.remove(for: key).value
            async let disk: Void = await onDisk.remove(for: key).value

            await memory
            await disk
        }
    }

    @discardableResult
    public nonisolated func removeAll() -> Task<Void, Never> {
        return Task {
            let task = await _removeAll()
            await task.value
        }
    }

    private func _removeAll() -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            async let memory: Void = await onMemery.removeAll().value
            async let disk: Void = await onDisk.removeAll().value

            await memory
            await disk
        }
    }

    public func url(for key: Key) async -> URL? {
        await onDisk.url(for: key)
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
