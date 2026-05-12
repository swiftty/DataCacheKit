import Testing
@testable import LRUCache
import Foundation

private func anyCache<Key, Value>(_ actual: some AnyCache<Key, Value>) -> any AnyCache<Key, Value> {
    actual
}

struct LRUCacheTests {
    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCostLimit(cache: any AnyCache<Int, Int>) {
        // Given
        cache.totalCostLimit = 10

        // When
        cache[1, cost: 4] = 1
        cache[2, cost: 5] = 2
        cache[3, cost: 5] = 3

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == 2)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimit(cache: any AnyCache<Int, Int>) {
        // Given
        cache.countLimit = 2

        // When
        cache[1] = 1
        cache[2] = 2
        cache[3] = 3

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == 2)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimitAccess(cache: any AnyCache<Int, Int>) {
        // Given
        cache.countLimit = 2

        // When
        cache[1] = 1
        cache[2] = 2

        _ = cache[1]
        cache[3] = 3

        // Then
        #expect(cache[1] == 1)
        #expect(cache[2] == nil)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimitWithCost1(cache: any AnyCache<Int, Int>) {
        // Given
        cache.countLimit = 2
        cache.totalCostLimit = 5

        // When
        cache[1, cost: 3] = 1
        cache[2, cost: 3] = 2
        cache[3, cost: 3] = 3

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == nil)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimitWithCost2(cache: any AnyCache<Int, Int>) {
        // Given
        cache.countLimit = 2
        cache.totalCostLimit = 3

        // When
        cache[1, cost: 3] = 1
        cache[2, cost: 2] = 2
        cache[3, cost: 1] = 3

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == 2)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimitWithCost3(cache: any AnyCache<Int, Int>) {
        // Given
        cache.countLimit = 2
        cache.totalCostLimit = 3

        // When
        cache[1, cost: 3] = 1
        cache[2, cost: 2] = 2
        cache[3, cost: 1] = 3
        cache[1, cost: 3] = 1

        // Then
        #expect(cache[1] == 1)
        #expect(cache[2] == nil)
        #expect(cache[3] == nil)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testCountLimitWithCost4(cache: any AnyCache<Int, Int>) {
        // Given
        cache.totalCostLimit = 10

        // When
        cache[1, cost: 3] = 1
        cache[2, cost: 2] = 2
        cache[3, cost: 1] = 3
        cache[1, cost: 3] = 1
        cache[3, cost: 7] = 3

        // Then
        #expect(cache[1] == 1)
        #expect(cache[2] == nil)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testRemoveHeadValue(cache: any AnyCache<Int, Int>) {
        // Given
        // -

        // When
        cache[1] = 1
        cache[2] = 2
        cache[3] = 3

        cache[1] = nil

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == 2)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testRemoveMiddleValue(cache: any AnyCache<Int, Int>) {
        // Given
        // -

        // When
        cache[1] = 1
        cache[2] = 2
        cache[3] = 3

        cache[2] = nil

        // Then
        #expect(cache[1] == 1)
        #expect(cache[2] == nil)
        #expect(cache[3] == 3)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testRemoveTailValue(cache: any AnyCache<Int, Int>) {
        // Given
        // -

        // When
        cache[1] = 1
        cache[2] = 2
        cache[3] = 3

        cache[3] = nil

        // Then
        #expect(cache[1] == 1)
        #expect(cache[2] == 2)
        #expect(cache[3] == nil)
    }

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, Int>()),
        anyCache(NSCacheWrapper<Int, Int>()),
    ])
    func testRemoveAll(cache: any AnyCache<Int, Int>) {
        // Given
        // -

        // When
        cache[1] = 1
        cache[2] = 2
        cache[3] = 3

        cache.removeAllValues()

        // Then
        #expect(cache[1] == nil)
        #expect(cache[2] == nil)
        #expect(cache[3] == nil)
    }

    final class MyClass: @unchecked Sendable {}

    @Test(arguments: [
        anyCache(LRUCacheWrapper<Int, MyClass>()),
        anyCache(NSCacheWrapper<Int, MyClass>()),
    ])
    func testReferenceCount(cache: any AnyCache<Int, MyClass>) {
        // Given
        var ref: MyClass? = MyClass()
        weak var weakRef = ref

        // When
        autoreleasepool {
            cache[1] = ref

            #expect(cache[1] === ref)

            ref = nil

            #expect(weakRef != nil)

            cache.removeAllValues()
        }

        // Then
        #expect(weakRef == nil)
    }
}

protocol AnyCache<Key, Value>: Sendable {
    associatedtype Key: Hashable
    associatedtype Value

    func value(forKey key: Key) -> Value?
    func setValue(_ value: Value, forKey key: Key, cost: Int)
    func removeValue(forKey key: Key)
    func removeAllValues()

    var totalCostLimit: Int { get nonmutating set }
    var countLimit: Int { get nonmutating set }

    subscript(_ key: Key, cost cost: Int) -> Value? { get nonmutating set }
}

extension AnyCache {
    func setValue(_ value: Value, forKey key: Key) {
        setValue(value, forKey: key, cost: 0)
    }

    subscript(_ key: Key, cost cost: Int = 0) -> Value? {
        get {
            value(forKey: key)
        }
        nonmutating set {
            if let newValue {
                setValue(newValue, forKey: key, cost: cost)
            } else {
                removeValue(forKey: key)
            }
        }
    }
}

// MARK: - private
private final class LRUCacheWrapper<Key: Hashable & Sendable, Value: Sendable>: AnyCache {
    func value(forKey key: Key) -> Value? {
        inner.value(forKey: key)
    }

    func setValue(_ value: Value, forKey key: Key, cost: Int = 0) {
        inner.setValue(value, forKey: key, cost: cost)
    }

    func removeValue(forKey key: Key) {
        inner.removeValue(forKey: key)
    }

    func removeAllValues() {
        inner.removeAllValues()
    }

    var totalCostLimit: Int {
        get { inner.totalCostLimit }
        set { inner.totalCostLimit = newValue }
    }

    var countLimit: Int {
        get { inner.countLimit }
        set { inner.countLimit = newValue }
    }

    // MARK: -
    private let inner = LRUCache<Key, Value>()
}

private final class NSCacheWrapper<Key: Hashable, Value>: AnyCache, @unchecked Sendable {
    func value(forKey key: Key) -> Value? {
        inner.object(forKey: .init(key))?.object
    }

    func setValue(_ value: Value, forKey key: Key, cost: Int = 0) {
        inner.setObject(.init(value), forKey: .init(key), cost: cost)
    }

    func removeValue(forKey key: Key) {
        inner.removeObject(forKey: .init(key))
    }

    func removeAllValues() {
        inner.removeAllObjects()
    }

    var totalCostLimit: Int {
        get { inner.totalCostLimit }
        set { inner.totalCostLimit = newValue }
    }

    var countLimit: Int {
        get { inner.countLimit }
        set { inner.countLimit = newValue }
    }

    // MARK: -

    private let inner = NSCache<KeyWrapper, ObjectWrapper>()

    private final class KeyWrapper: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let object = object as? KeyWrapper else { return false }
            return key == object.key
        }

        override var hash: Int {
            return key.hashValue
        }
    }

    private final class ObjectWrapper: NSObject {
        let object: Value

        init(_ object: Value) {
            self.object = object
        }
    }
}
