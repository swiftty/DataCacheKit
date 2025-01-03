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
            if let entry = entries.values[key] {
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

private extension LRUCache {
    final class CacheEntry: @unchecked Sendable {
        let key: Key
        var value: Value
        var cost: Int
        var prevByCost: CacheEntry?
        var nextByCost: CacheEntry?

        init(key: Key, value: Value, cost: Int) {
            self.key = key
            self.value = value
            self.cost = cost
            self.prevByCost = nil
            self.nextByCost = nil
        }
    }

    struct Entiries: Sendable {
        var values: [Key: CacheEntry] = [:]
        var totalCost = 0
        var totalCostLimit = 0
        var countLimit = 0
        var head: CacheEntry?

        mutating func set(_ value: Value, forKey key: Key, cost g: Int) {
            let g = max(g, 0)

            let costDiff: Int

            if let entry = values[key] {
                costDiff = g - entry.cost
                entry.cost = g
                entry.value = value

                if costDiff != 0 {
                    remove(entry)
                    insert(entry)
                }
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
            guard var curr = head else {
                entry.prevByCost = nil
                entry.nextByCost = nil

                head = entry
                return
            }

            guard entry.cost > curr.cost else {
                entry.prevByCost = nil
                entry.nextByCost = curr
                curr.prevByCost = entry

                head = entry
                return
            }

            while let next = curr.nextByCost, next.cost < entry.cost {
                curr = next
            }

            let next = curr.nextByCost

            curr.nextByCost = entry
            entry.prevByCost = curr

            entry.nextByCost = next
            next?.prevByCost = entry
        }

        mutating func remove(_ entry: CacheEntry) {
            let oldPrev = entry.prevByCost
            let oldNext = entry.nextByCost

            oldPrev?.nextByCost = oldNext
            oldNext?.prevByCost = oldPrev

            if entry === head {
                head = oldNext
            }
        }

        mutating func removeAll() {
            values.removeAll()

            while let curr = head {
                let next = curr.nextByCost

                curr.prevByCost = nil
                curr.nextByCost = nil

                head = next
            }

            totalCost = 0
        }
    }
}

