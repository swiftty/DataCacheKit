import Testing
@testable import DataCacheKit
import Foundation

struct LRUCacheTests {
    @Test
    func testCountLimit() {
        let cache = LRUCache<Int, Int>()

        // Given
        cache.countLimit = 2

        // When
        cache.setValue(1, forKey: 1)
        cache.setValue(2, forKey: 2)
        cache.setValue(3, forKey: 3)

        // Then
        #expect(cache.value(forKey: 1) == nil)
        #expect(cache.value(forKey: 2) == 2)
        #expect(cache.value(forKey: 3) == 3)
    }

    @Test
    func testCountLimitNSCache() {
        let cache = NSCache<NSNumber, NSNumber>()

        // Given
        cache.countLimit = 2

        // When
        cache.setObject(1, forKey: 1)
        cache.setObject(2, forKey: 2)
        cache.setObject(3, forKey: 3)

        // Then
        #expect(cache.object(forKey: 1) == nil)
        #expect(cache.object(forKey: 2) == 2)
        #expect(cache.object(forKey: 3) == 3)
    }
}
