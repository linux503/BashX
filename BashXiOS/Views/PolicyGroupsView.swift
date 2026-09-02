import SwiftUI

/// Shadowrocket-style policy group list: business name → current selection → pick member.
struct PolicyGroupsView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    /// The main 策略组 (PROXY select). Everything else (电报/谷歌/区域…) is hidden here.
    private var hubGroup: VPNManager.ProxyGroupSnapshot? {
        state.proxyGroups.first { $0.name.uppercased() == "PROXY" }
    }

    /// Strategy hubs available inside PROXY, in fixed order: 智能 / 均衡 / 故障转移.
    private func strategies(in group: VPNManager.ProxyGroupSnapshot) -> [String] {
        let order = ["AUTO", "BALANCE", "FALLBACK"]
        let members = Set(group.all.map { $0.uppercased() })
        return order.filter { members.contains($0) }
    }

    private func strategyTitle(_ name: String) -> String {
        switch name.uppercased() {
        case "AUTO": return t("groups.strategy.smart")
        case "BALANCE": return t("groups.strategy.balance")
        case "FALLBACK": return t("groups.strategy.failover")
        default: return AppConstants.groupDisplayName(name)
        }
    }

    private func strategyIcon(_ name: String) -> String {
        switch name.uppercased() {
        case "BALANCE": return "arrow.triangle.2.circlepath"
        case "FALLBACK": return "arrow.right.to.line.circle.fill"
        default: return "bolt.horizontal.circle.fill"
        }
    }

    var body: some View {
        NavigationStack {
            IOSPageBackground {
                Group {
                    if !vpn.isConnected {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(t("groups.needVpn"))
                                .font(.headline)
                            Text(t("home.groupsEmpty"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if state.proxyGroups.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(t("groups.loading"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(t("groups.refresh")) {
                                state.scheduleProxyGroupsRefresh()
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let hub = hubGroup, !strategies(in: hub).isEmpty {
                        // Only the main 策略组: pick between 智能策略 / 负载均衡 / 故障转移.
                        List {
                            Section {
                                ForEach(strategies(in: hub), id: \.self) { name in
                                    Button {
                                        state.selectGroupProxy(group: hub.name, name: name)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: strategyIcon(name))
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(IOSTheme.accent)
                                                .frame(width: 24)
                                            Text(strategyTitle(name))
                                                .font(.system(.body, design: .rounded).weight(.medium))
                                                .foregroundStyle(.primary)
                                            Spacer(minLength: 8)
                                            if name.uppercased() == hub.now.uppercased() {
                                                Image(systemName: "checkmark")
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(IOSTheme.accent)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(t("groups.title"))
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    } else {
                        // Fallback for subscription profiles without our PROXY hub: full group list.
                        List {
                            ForEach(state.proxyGroups) { group in
                                NavigationLink {
                                    PolicyGroupMemberPicker(group: group)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(AppConstants.groupDisplayName(group.name))
                                            .font(.system(.body, design: .rounded).weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 8)
                                        Text(AppConstants.groupSelectionLabel(group.now, limit: 20))
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(t("groups.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("home.refresh")) {
                        state.scheduleProxyGroupsRefresh()
                    }
                    .disabled(!vpn.isConnected)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("common.done")) { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task(id: vpn.isConnected) {
            guard vpn.isConnected else { return }
            for attempt in 0..<4 {
                await state.refreshProxyGroups()
                if !state.proxyGroups.isEmpty { break }
                try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
            }
        }
    }
}

private struct PolicyGroupMemberPicker: View {
    @EnvironmentObject private var state: IOSAppState
    let group: VPNManager.ProxyGroupSnapshot

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var liveGroup: VPNManager.ProxyGroupSnapshot {
        state.proxyGroups.first(where: { $0.name == group.name }) ?? group
    }

    var body: some View {
        List {
            ForEach(liveGroup.all, id: \.self) { name in
                Button {
                    state.selectGroupProxy(group: liveGroup.name, name: name)
                } label: {
                    HStack {
                        Text(AppConstants.groupSelectionLabel(name, limit: 36))
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        if name == liveGroup.now {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(IOSTheme.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppConstants.groupDisplayName(liveGroup.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
