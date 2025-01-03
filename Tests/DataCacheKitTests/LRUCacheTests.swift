import Testing
@testable import DataCacheKit
import Foundation

struct LRUCacheTests {
    @Test
    func testCostLimit() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCostLimitNSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testCountLimit() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCountLimitNSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testCountLimitWithCost1() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCountLimitWithCost1NSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testCountLimitWithCost2() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCountLimitWithCost2NSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testCountLimitWithCost3() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCountLimitWithCost3NSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testCountLimitWithCost4() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testCountLimitWithCost4NSCache() {
        let cache = NSCacheWrapper<Int, Int>()

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

    @Test
    func testRemoveHeadValue() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testRemoveMiddleValue() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testRemoveTailValue() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testRemoveAll() {
        let cache = LRUCache<Int, Int>()

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

    @Test
    func testReferenceCount() {
        final class MyClass: @unchecked Sendable {}

        let cache = LRUCache<Int, MyClass>()

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

// MARK: - private
private final class NSCacheWrapper<Key: Hashable, Object> {
    func object(forKey key: Key) -> Object? {
        inner.object(forKey: .init(key))?.object
    }

    func setObject(_ obj: Object, forKey key: Key, cost: Int = 0) {
        inner.setObject(.init(obj), forKey: .init(key), cost: cost)
    }

    func removeObject(forKey key: Key) {
        inner.removeObject(forKey: .init(key))
    }

    func removeAllObjects() {
        inner.removeAllObjects()
    }

    func removeAllValues() {
        removeAllObjects()
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
        let object: Object

        init(_ object: Object) {
            self.object = object
        }
    }
}

extension NSCacheWrapper {
    subscript (_ key: Key, cost cost: Int = 0) -> Object? {
        get {
            object(forKey: key)
        }
        set {
            if let newValue {
                setObject(newValue, forKey: key, cost: cost)
            } else {
                removeObject(forKey: key)
            }
        }
    }
}
