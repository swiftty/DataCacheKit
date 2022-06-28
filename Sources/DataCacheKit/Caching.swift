import Foundation

public protocol Caching<Key, Value>: Sendable {
    associatedtype Key: Hashable & Sendable
    associatedtype Value

    subscript (key: Key) -> Value? { get async throws }

    func value(for key: Key) async throws -> Value?

    @discardableResult
    func store(_ value: Value, for key: Key) -> Task<Void, Never>

    @discardableResult
    func remove(for key: Key) -> Task<Void, Never>

    @discardableResult
    func removeAll() -> Task<Void, Never>
}
