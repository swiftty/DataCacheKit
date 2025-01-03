# DataCacheKit

A simple data cache interface.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/swiftty/DataCacheKit", from: "0.1.0")
]
```

## Usage

```swift
import DataCacheKit

// You can choose MemoryCache<<#Key#>, <#Value#>> or Cache<<#Key#>, <#Value#>> as well as DiskCache<<#Key#>>.
let cache = DiskCache<String>(options: .default(path: .default("caches")))

// read
try await cache.value(for: "item0")

// write
cache.store(Data(), for: "item0")

// remove
cache.remove(for: "item0")

// remove all
cache.removeAll()
```

## License

DataCacheKit is available under the MIT license, and uses source code from open source projects. See the [LICENSE](https://github.com/swiftty/DataCacheKit/blob/main/LICENSE) file for more info.
