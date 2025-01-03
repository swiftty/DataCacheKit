import Foundation

public protocol Caching<Key, Value>: Actor {
    associatedtype Key: Hashable & Sendable
    associatedtype Value

    subscript (key: Key) -> Value? { get async throws }

    func value(for key: Key) async throws -> Value?

    @discardableResult
    nonisolated func store(_ value: Value, for key: Key) -> Task<Void, Never>

    @discardableResult
    nonisolated func remove(for key: Key) -> Task<Void, Never>

    @discardableResult
    nonisolated func removeAll() -> Task<Void, Never>
}
