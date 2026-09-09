import AppKit
import SwiftUI

@main
struct CodexQuotaMenuApp: App {
    @StateObject private var model: QuotaViewModel

    init() {
        let model = QuotaViewModel()
        _model = StateObject(wrappedValue: model)
        DispatchQueue.main.async {
            model.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaPanel(model: model)
        } label: {
            Text(model.menuBarTitle)
                .monospacedDigit()
                .accessibilityLabel(model.accessibilityStatus)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct QuotaPanel: View {
    @ObservedObject var model: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 额度")
                        .font(.title3.weight(.semibold))
                    if let planType = model.snapshot?.planType {
                        Text(planType.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .fill(model.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(model.isConnected ? "已连接" : "未连接")
                }
            }

            if let window = model.snapshot?.main.primary {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Codex")
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline) {
                        Text(window.windowName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("剩余 \(window.remainingPercent)%")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }

                    QuotaProgressView(remainingPercent: window.remainingPercent)

                    Text("\(QuotaFormatter.resetDetail(until: window.resetsAt)) 重置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 5) {
                    Text("暂时无法读取额度")
                        .font(.subheadline.weight(.medium))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("正在连接 Codex…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .modifier(GlassCardModifier())
        .padding(8)
        .frame(width: 300)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                model.refresh()
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
                .disabled(model.isRefreshing)

            Divider()

            Button("退出") {
                model.stop()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct QuotaProgressView: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * CGFloat(remainingPercent) / 100)
            }
        }
        .frame(height: 7)
        .accessibilityElement()
        .accessibilityLabel("额度剩余")
        .accessibilityValue("\(remainingPercent)%")
    }
}

private struct GlassCardModifier: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape
                        .stroke(.white.opacity(0.16), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
    }
}
