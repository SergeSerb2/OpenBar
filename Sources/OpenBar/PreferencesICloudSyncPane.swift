import OpenBarCore
import SwiftUI

@MainActor
struct ICloudSyncPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var state: CloudSyncState
    private static let securityFootnote =
        "Secrets use iCloud end-to-end encryption via encryptedValues. " +
        "Hooks and machine-local paths never sync."

    /// The engine records `.missingEntitlement` from `CloudSyncEntitlementGate` when it starts. The pane also
    /// reads the gate itself so a window opened before that start never shows sync controls that would fail.
    private static let buildHasCloudKitEntitlement = CloudSyncEntitlementGate.hasICloudServicesEntitlement()

    static func isAvailableInThisBuild(availability: SyncAvailability, hasEntitlement: Bool) -> Bool {
        hasEntitlement && availability != .missingEntitlement
    }

    var body: some View {
        if Self.isAvailableInThisBuild(
            availability: self.state.availability,
            hasEntitlement: Self.buildHasCloudKitEntitlement)
        {
            self.syncForm
        } else {
            Form {
                Section {
                    Label {
                        Text(L("iCloud Sync is not available in this build of OpenBar."))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .settingsPaneForm()
        }
    }

    private var syncForm: some View {
        Form {
            if self.state.status.needsAppUpdate {
                Section {
                    SettingsStatusMessage(
                        L("Sync is paused: another Mac uses a newer version of OpenBar. Update to resume."),
                        tone: .warning)
                }
            }

            Section {
                Toggle(
                    L("Sync settings and providers across your Macs via iCloud"),
                    isOn: self.primarySyncBinding)
                    .toggleStyle(.checkbox)
                    .disabled(!self.syncCanBeEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(L("Include API keys, cookies, and tokens"), isOn: self.includeSecretsBinding)
                    Toggle(L("Sync usage snapshots"), isOn: self.snapshotsBinding)
                    Toggle(L("Show accounts from other Macs"), isOn: self.showFleetAccountsBinding)
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 20)
                .disabled(!self.syncCanRun || !self.settings.iCloudSyncEnabled)
            } header: {
                Text(L("iCloud Sync"))
            } footer: {
                if let availabilityMessage = self.availabilityMessage {
                    SettingsSectionFooter(availabilityMessage)
                }
            }

            Section {
                LabeledContent(
                    L("Last successful fetch"),
                    value: self.relativeTime(self.state.status.lastSuccessfulFetchAt))
                LabeledContent(
                    L("Last successful push"),
                    value: self.relativeTime(self.state.status.lastSuccessfulPushAt))
            } header: {
                Text(L("Status"))
            }

            Section {
                if self.devices.isEmpty {
                    Text(L("No synced Macs yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(self.devices, id: \.deviceID) { device in
                        HStack {
                            ICloudSyncDeviceRow(
                                device: device,
                                isCurrentDevice: device.deviceID == self.settings.iCloudSyncDeviceID)
                            if device.deviceID != self.settings.iCloudSyncDeviceID {
                                Button(L("Remove"), role: .destructive) {
                                    Task { await self.state.requestDeviceRemoval(device.deviceID) }
                                }
                                .disabled(!self.syncCanRun || !self.settings.iCloudSyncEnabled)
                            }
                        }
                    }
                }
            } header: {
                Text(L("Macs"))
            } footer: {
                SettingsSectionFooter(L(Self.securityFootnote))
            }
        }
        .settingsPaneForm()
    }

    private var syncCanBeEnabled: Bool {
        self.state.availability == .available
    }

    private var syncCanRun: Bool {
        self.syncCanBeEnabled && !self.state.status.needsAppUpdate
    }

    private var availabilityMessage: String? {
        switch self.state.availability {
        case .available:
            nil
        case .missingEntitlement:
            L("Requires a signed release build of OpenBar.")
        case .noICloudAccount:
            L("Sign in to iCloud in System Settings to enable sync.")
        case .restricted:
            L("iCloud access is restricted on this Mac.")
        }
    }

    private var devices: [DeviceSyncPayload] {
        self.state.fleetDevices.values.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.deviceID == self.settings.iCloudSyncDeviceID
            let rhsIsCurrent = rhs.deviceID == self.settings.iCloudSyncDeviceID
            if lhsIsCurrent != rhsIsCurrent {
                return lhsIsCurrent
            }
            if lhs.lastSeen != rhs.lastSeen {
                return lhs.lastSeen > rhs.lastSeen
            }
            return lhs.hostName.localizedCaseInsensitiveCompare(rhs.hostName) == .orderedAscending
        }
    }

    private var primarySyncBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncEnabled },
            set: { self.settings.iCloudSyncEnabled = $0 })
    }

    private var includeSecretsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncIncludeSecrets },
            set: { self.settings.iCloudSyncIncludeSecrets = $0 })
    }

    private var snapshotsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncSnapshotsEnabled },
            set: { self.settings.iCloudSyncSnapshotsEnabled = $0 })
    }

    private var showFleetAccountsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncShowFleetAccounts },
            set: { self.settings.iCloudSyncShowFleetAccounts = $0 })
    }

    private func relativeTime(_ date: Date?) -> String {
        date?.relativeDescription() ?? L("Never")
    }
}

private struct ICloudSyncDeviceRow: View {
    let device: DeviceSyncPayload
    let isCurrentDevice: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.device.hostName)
                Text(String(format: L("Last seen %@"), self.device.lastSeen.relativeDescription()))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if self.isCurrentDevice {
                Text(L("This Mac"))
                    .font(OpenBarTheme.Fonts.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, OpenBarSpacing.compact)
                    .padding(.vertical, OpenBarSpacing.hairline)
                    .background(SettingsFillBackground(shape: RoundedRectangle(
                        cornerRadius: OpenBarRadius.chip,
                        style: .continuous)))
            }
        }
    }
}
