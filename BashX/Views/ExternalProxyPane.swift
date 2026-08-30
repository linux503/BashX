import AppKit
import SwiftUI

/// Configure mixed-port proxy for other apps (curl / browsers / IDE).
struct ExternalProxyPane: View {
    @EnvironmentObject private var state: AppState
    @State private var portText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PanelSection(title: "外置代理") {
                    Text("HTTP / SOCKS5 共用 mixed-port 端口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.coreRunning ? "内核运行中，可连接" : "需先启动内核")
                        .font(.caption)
                        .foregroundStyle(state.coreRunning ? BashXTheme.good : .secondary)

                    proxyLine(title: "地址", value: state.externalProxyAddress)
                    proxyLine(title: "HTTP", value: state.externalProxyHTTPURL)
                    proxyLine(title: "SOCKS5", value: state.externalProxySOCKSURL)

                    HStack(spacing: 6) {
                        copyBtn("地址") { state.copyExternalProxy(kind: .hostPort) }
                        copyBtn("HTTP") { state.copyExternalProxy(kind: .http) }
                        copyBtn("SOCKS") { state.copyExternalProxy(kind: .socks) }
                        copyBtn("环境变量") { state.copyExternalProxy(kind: .exportEnv) }
                    }
                }

                PanelSection(title: "端口") {
                    HStack(spacing: 8) {
                        TextField("17890", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(width: 88)
                        Button("应用") {
                            if let p = Int(portText.trimmingCharacters(in: .whitespaces)) {
                                Task { await state.setMixedPort(p) }
                            }
                        }
                        .controlSize(.small)
                        .disabled(Int(portText) == state.settings.mixedPort)
                        Spacer()
                    }

                    Toggle(isOn: Binding(
                        get: { state.settings.allowLan },
                        set: { v in Task { await state.setAllowLan(v) } }
                    )) {
                        Text(state.settings.allowLan
                             ? "允许局域网 · \(state.externalProxyAddress)"
                             : "仅本机 127.0.0.1:\(state.settings.mixedPort)")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                PanelSection(title: "示例") {
                    exampleRow("终端", "export https_proxy=\(state.externalProxyHTTPURL)")
                    exampleRow("curl", "curl -x \(state.externalProxyHTTPURL) https://www.google.com")
                }
            }
            .padding(16)
        }
        .onAppear { portText = "\(state.settings.mixedPort)" }
        .onValueChange(state.settings.mixedPort) { v in portText = "\(v)" }
    }

    private func proxyLine(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func copyBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .controlSize(.mini)
    }

    private func exampleRow(_ title: String, _ sample: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(sample).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
