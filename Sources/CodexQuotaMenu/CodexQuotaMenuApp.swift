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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 额度")
                        .font(.headline)
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

            if let snapshot = model.snapshot {
                ForEach(snapshot.allBuckets) { bucket in
                    BucketView(bucket: bucket)
                    if bucket.id != snapshot.allBuckets.last?.id {
                        Divider()
                    }
                }

                Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Divider()

            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

                Spacer()

                Button("退出") {
                    model.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 286)
    }
}

private struct BucketView: View {
    let bucket: QuotaBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bucket.name)
                .font(.subheadline.weight(.medium))

            ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(window.windowName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("剩余 \(window.remainingPercent)%")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }

                    ProgressView(value: Double(window.remainingPercent), total: 100)

                    Text("\(QuotaFormatter.resetDetail(until: window.resetsAt)) 重置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
