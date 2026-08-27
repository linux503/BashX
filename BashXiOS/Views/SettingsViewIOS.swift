import SwiftUI

struct SettingsViewIOS: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("连接状态", value: vpn.statusText)
                    LabeledContent("当前节点") {
                        Text(state.settings.selectedNodeName ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent("出站 IP") {
                        HStack {
                            Text(state.outboundIPLoading ? "查询中…" : state.outboundIP)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button {
                                Task { await state.refreshOutboundIP() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(!vpn.isConnected)
                        }
                    }
                    LabeledContent("分流模式", value: state.settings.proxyMode.title)
                } header: {
                    Text("状态")
                }

                Section {
                    Stepper(value: $state.settings.testTimeoutMs, in: 1000...8000, step: 500) {
                        HStack {
                            Text("测速超时")
                            Spacer()
                            Text("\(state.settings.testTimeoutMs) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $state.settings.concurrency, in: 2...16) {
                        HStack {
                            Text("测速并发")
                            Spacer()
                            Text("\(state.settings.concurrency)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("测速")
                }

                Section {
                    Picker("DNS 优选", selection: Binding(
                        get: { state.settings.dnsPreference },
                        set: { state.setDnsPreference($0) }
                    )) {
                        ForEach(DnsPreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    }
                    Text(state.settings.dnsPreference.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("DNS")
                } footer: {
                    Text("默认「智能分流」：国内域名走阿里/腾讯 DoH，被墙域名回落 Cloudflare/Google。修改后若 VPN 已连接，请断开再连一次。")
                }

                Section {
                    LabeledContent("规则基准") {
                        Text("v\(state.settings.rulesVersion > 0 ? state.settings.rulesVersion : ChinaSmartRules.version)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    LabeledContent("生效条数") {
                        Text("\(state.effectiveRuntimeRules().count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Toggle("视频广告过滤", isOn: Binding(
                        get: { state.settings.videoAdBlockEnabled },
                        set: { state.setVideoAdBlock($0) }
                    ))
                    Button {
                        state.applySmartRules()
                    } label: {
                        Label("恢复 BashX 智能规则 v\(ChinaSmartRules.version)", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("智能分流")
                } footer: {
                    Text("与 Mac 版相同规则：国内直连、广告拦截、国外走代理。iOS 会自动去掉进程名规则（GEOSITE 已覆盖）。")
                }

                Section {
                    LabeledContent("版本", value: "0.1.0")
                    Text("首次连接 VPN 时请允许系统权限。建议保持竖屏使用以获得最佳布局。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .tint(IOSTheme.accent)
            .onChange(of: state.settings.testTimeoutMs) { _ in state.persist() }
            .onChange(of: state.settings.concurrency) { _ in state.persist() }
        }
    }
}
