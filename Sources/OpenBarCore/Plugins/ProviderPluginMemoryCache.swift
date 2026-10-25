import Foundation

/// JSON-only ephemeral state; validated cookie providers may reuse it across strategy instances.
final class ProviderPluginMemoryCache: @unchecked Sendable {
    static let shared = ProviderPluginMemoryCache()
    static let maximumEntries = 128
    static let maximumKeyBytes = 128
    static let maximumValueBytes = 16384
    private let lock = NSLock()
    private var entries: [String: (json: String, expires: Date)] = [:]

    func get(namespace: String, key: String) -> String? {
        self.lock.withLock {
            let key = namespace + ":" + key
            guard let entry = self.entries[key], entry.expires > Date() else {
                self.entries[key] = nil
                return nil
            }
            return entry.json
        }
    }

    func set(namespace: String, key: String, json: String, ttl: Double) {
        guard key.utf8.count <= Self.maximumKeyBytes, json.utf8.count <= Self.maximumValueBytes, ttl.isFinite, ttl > 0
        else { return }
        self.lock.withLock {
            self.entries = self.entries.filter { $0.value.expires > Date() }
            let key = namespace + ":" + key
            guard self.entries[key] != nil || self.entries.count < Self.maximumEntries else { return }
            self.entries[key] = (json, Date().addingTimeInterval(min(ttl, 86400)))
        }
    }
}

/// One runtime's `ctx.cache`, bounded like the shared cache so a plugin cannot grow host memory without limit:
/// expired entries are purged on every write, and oversized or overflowing writes are not stored.
struct ProviderPluginRuntimeCache<Value> {
    private var entries: [String: (value: Value, expires: Date)] = [:]

    mutating func get(_ key: String, now: Date = Date()) -> Value? {
        guard let entry = self.entries[key], entry.expires > now else {
            self.entries[key] = nil
            return nil
        }
        return entry.value
    }

    mutating func set(_ key: String, value: Value, valueBytes: Int, ttl: Double, now: Date = Date()) {
        guard ttl.isFinite, ttl > 0 else { return }
        self.entries = self.entries.filter { $0.value.expires > now }
        guard key.utf8.count <= ProviderPluginMemoryCache.maximumKeyBytes,
              valueBytes <= ProviderPluginMemoryCache.maximumValueBytes
        else {
            // A rejected write must not leave an older value readable under the same key.
            self.entries[key] = nil
            return
        }
        guard self.entries[key] != nil || self.entries.count < ProviderPluginMemoryCache.maximumEntries else { return }
        self.entries[key] = (value, now.addingTimeInterval(min(ttl, 86400)))
    }
}
