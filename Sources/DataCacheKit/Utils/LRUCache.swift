// https://github.com/swiftlang/swift-corelibs-foundation/blob/25d044f2c4ceb635d9f714f588673fd7a29790c1/Sources/Foundation/NSCache.swift
import os

struct LRUCache<Key: Hashable & Sendable, Value: Sendable>: ~Copyable, Sendable {
    var totalCostLimit: Int {
        get { entries.withLock { $0.totalCostLimit } }
        nonmutating set { entries.withLock { $0.totalCostLimit = newValue } }
    }

    var countLimit: Int {
        get { entries.withLock { $0.countLimit } }
        nonmutating set { entries.withLock { $0.countLimit = newValue } }
    }

    private let entries = OSAllocatedUnfairLock<Entiries>(initialState: .init())

    func value(forKey key: Key) -> Value? {
        entries.withLock { entries in
            entries.values[key]?.value
        }
    }

    func setValue(_ value: Value, forKey key: Key) {
        setValue(value, forKey: key, cost: 0)
    }

    func setValue(_ value: Value, forKey key: Key, cost: Int) {
        entries.withLock { entries in
            entries.set(value, forKey: key, cost: cost)
        }
    }

    func removeValue(forKey key: Key) {
        entries.withLock { entries in
            if let entry = entries.values.removeValue(forKey: key) {
                entries.totalCost -= entry.cost
                entries.remove(entry)
            }
        }
    }

    func removeAllValues() {
        entries.withLock { entiries in
            entiries.removeAll()
        }
    }
}

extension LRUCache {
    subscript (_ key: Key, cost cost: Int = 0) -> Value? {
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

private extension LRUCache {
    final class CacheEntry: @unchecked Sendable {
        let key: Key
        var value: Value
        var cost: Int
        weak var prev: CacheEntry?
        weak var next: CacheEntry?

        init(key: Key, value: Value, cost: Int) {
            self.key = key
            self.value = value
            self.cost = cost
            self.prev = nil
            self.next = nil
        }
    }

    struct Entiries: Sendable {
        var values: [Key: CacheEntry] = [:]
        var totalCost = 0
        var totalCostLimit = 0
        var countLimit = 0
        weak var head: CacheEntry?
        weak var tail: CacheEntry?

        mutating func set(_ value: Value, forKey key: Key, cost g: Int) {
            let g = max(g, 0)

            let costDiff: Int

            if let entry = values[key] {
                costDiff = g - entry.cost
                entry.cost = g
                entry.value = value

                remove(entry)
                insert(entry)
            } else {
                let entry = CacheEntry(key: key, value: value, cost: g)
                values[key] = entry
                insert(entry)

                costDiff = g
            }

            totalCost += costDiff

            var purgeAmount = totalCostLimit > 0 ? totalCost - totalCostLimit : 0
            while purgeAmount > 0, let entry = head {
                totalCost -= entry.cost
                purgeAmount -= entry.cost

                remove(entry)
                values[entry.key] = nil
            }

            var purgeCount = countLimit > 0 ? values.count - countLimit : 0
            while purgeCount > 0, let entry = head {
                totalCost -= entry.cost
                purgeCount -= 1

                remove(entry)
                values[entry.key] = nil
            }
        }

        mutating func insert(_ entry: CacheEntry) {
            guard head != nil else {
                entry.prev = nil
                entry.next = nil

                head = entry
                tail = entry
                return
            }

            tail?.next = entry
            entry.prev = tail
            tail = entry
        }

        mutating func remove(_ entry: CacheEntry) {
            let oldPrev = entry.prev
            let oldNext = entry.next

            oldPrev?.next = oldNext
            oldNext?.prev = oldPrev

            if entry === head {
                head = oldNext
            }
            if entry === tail {
                tail = oldPrev
            }
        }

        mutating func removeAll() {
            values.removeAll()
            totalCost = 0

            assert(head == nil && tail == nil)
        }
    }
}
