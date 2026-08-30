import SwiftUI

/// Shadowrocket-style policy group list: business name → current selection → pick member.
struct PolicyGroupsView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

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
                    } else {
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
        .onAppear {
            if vpn.isConnected {
                state.scheduleProxyGroupsRefresh()
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
