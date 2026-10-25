import Foundation

extension OpenBarConfig {
    /// Rebase an app edit onto the config read under the process-shared write lock.
    /// Unchanged fields and opaque unavailable-provider records belong to the latest file.
    package func applyingChanges(from original: Self, to edited: Self) throws -> Self {
        var result = self
        if original.version != edited.version { result.version = edited.version }
        if original.shareUsageWithCLI != edited.shareUsageWithCLI {
            result.shareUsageWithCLI = edited.shareUsageWithCLI
        }
        result.hooks = try ConfigValueChanges.apply(from: original.hooks, to: edited.hooks, current: self.hooks)
        let originalIDs = Set(original.providers.map(\.id))
        let editedIDs = Set(edited.providers.map(\.id))
        result.providers.removeAll { originalIDs.contains($0.id) && !editedIDs.contains($0.id) }
        for provider in edited.providers {
            let before = original.providerConfig(for: provider.id)
            let latest = result.providerConfig(for: provider.id)
            let entry = try ConfigValueChanges.apply(from: before, to: provider, current: latest)
            if var entry {
                entry.tokenAccounts = Self.rebasingActiveAccount(
                    entry.tokenAccounts,
                    original: before?.tokenAccounts,
                    edited: provider.tokenAccounts,
                    current: latest?.tokenAccounts)
                result.setProviderConfig(entry)
            }
        }
        if original.providers.map(\.id) != edited.providers.map(\.id) {
            let entries = Dictionary(uniqueKeysWithValues: result.providers.map { ($0.id, $0) })
            result.providers = edited.providers.compactMap { entries[$0.id] }
                + result.providers.filter { !editedIDs.contains($0.id) }
        }
        return result.normalized()
    }

    /// Accounts merge by ID, so the active index must follow the selected account rather than its old slot.
    private static func rebasingActiveAccount(
        _ merged: ProviderTokenAccountData?,
        original: ProviderTokenAccountData?,
        edited: ProviderTokenAccountData?,
        current: ProviderTokenAccountData?) -> ProviderTokenAccountData?
    {
        guard let merged, !merged.accounts.isEmpty else { return merged }
        func activeID(_ data: ProviderTokenAccountData?) -> UUID? {
            guard let data, !data.accounts.isEmpty else { return nil }
            return data.accounts[data.clampedActiveIndex()].id
        }
        let editedID = activeID(edited)
        let selected = editedID != activeID(original) ? editedID : activeID(current)
        guard let selected, let index = merged.accounts.firstIndex(where: { $0.id == selected }) else { return merged }
        return ProviderTokenAccountData(version: merged.version, accounts: merged.accounts, activeIndex: index)
    }
}

private enum ConfigValueChanges {
    static func apply<Value: Codable>(from original: Value?, to edited: Value?, current: Value?) throws -> Value? {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        func value(_ input: Value?) throws -> ProviderConfigExtensionValue? {
            try input.map { try decoder.decode(ProviderConfigExtensionValue.self, from: encoder.encode($0)) }
        }
        guard let merged = try self.merge(original: value(original), edited: value(edited), current: value(current))
        else { return nil }
        return try decoder.decode(Value.self, from: encoder.encode(merged))
    }

    private static func merge(
        original: ProviderConfigExtensionValue?,
        edited: ProviderConfigExtensionValue?,
        current: ProviderConfigExtensionValue?) -> ProviderConfigExtensionValue?
    {
        guard original != edited else { return current }
        guard let edited else { return nil }
        if case let .object(after) = edited {
            let before: [String: ProviderConfigExtensionValue] = if case let .object(fields) = original {
                fields
            } else { [:] }
            var latest: [String: ProviderConfigExtensionValue] = if case let .object(fields) = current {
                fields
            } else { [:] }
            for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
                latest[key] = self.merge(original: before[key], edited: after[key], current: latest[key])
            }
            return .object(latest)
        }
        if case let .array(before) = original, case let .array(after) = edited,
           case let .array(latest) = current,
           let beforeIDs = self.ids(before), let afterIDs = self.ids(after), let latestIDs = self.ids(latest)
        {
            let old = Dictionary(uniqueKeysWithValues: zip(beforeIDs, before))
            let new = Dictionary(uniqueKeysWithValues: zip(afterIDs, after))
            let existing = Dictionary(uniqueKeysWithValues: zip(latestIDs, latest))
            let order = beforeIDs == afterIDs ? latestIDs : afterIDs + latestIDs.filter { new[$0] == nil }
            return .array(order.compactMap { id in
                self.merge(
                    original: old[id],
                    edited: new[id] ?? (old[id] == nil ? existing[id] : nil),
                    current: existing[id])
            })
        }
        return edited
    }

    private static func ids(_ entries: [ProviderConfigExtensionValue]) -> [String]? {
        let ids = entries.compactMap { entry -> String? in
            guard case let .object(fields) = entry, case let .string(id) = fields["id"] else { return nil }
            return id
        }
        return ids.count == entries.count && Set(ids).count == ids.count ? ids : nil
    }
}
