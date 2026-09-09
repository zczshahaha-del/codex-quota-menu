import AppKit
import Combine
import SwiftUI

@main
struct CodexQuotaMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.stop()
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let model = QuotaViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: NSPanel!
    private var hostingView: NSHostingView<QuotaPanel>!
    private var modelObservation: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var lastStatusItemInteraction = Date.distantPast

    override init() {
        super.init()
        configureStatusItem()
        configurePanel()

        modelObservation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshPresentation()
            }
        }

        updateStatusItem()
        model.start()
    }

    func stop() {
        removeOutsideClickMonitor()
        model.stop()
        panel?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = model.menuBarTitle
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.setButtonType(.toggle)
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePanel() {
        let hostingView = NSHostingView(rootView: QuotaPanel(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.panel = panel
    }

    @objc private func togglePanel() {
        lastStatusItemInteraction = Date()
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        resizeAndPositionPanel()
        statusItem.button?.state = .on
        panel.orderFrontRegardless()
        installOutsideClickMonitor()
    }

    private func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.state = .off
        removeOutsideClickMonitor()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = model.menuBarTitle
        button.toolTip = model.accessibilityStatus
        button.setAccessibilityLabel(model.accessibilityStatus)
    }

    private func refreshPresentation() {
        updateStatusItem()
        guard panel.isVisible else { return }

        DispatchQueue.main.async { [weak self] in
            self?.resizeAndPositionPanel()
        }
    }

    private func resizeAndPositionPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        panel.setContentSize(contentSize)
        hostingView.frame = NSRect(origin: .zero, size: contentSize)

        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let anchor = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame
        let horizontalMargin: CGFloat = 8
        var x = anchor.midX - contentSize.width / 2
        x = max(visibleFrame.minX + horizontalMargin, x)
        x = min(visibleFrame.maxX - contentSize.width - horizontalMargin, x)
        let y = anchor.minY - contentSize.height - 6

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let clickLocation = NSEvent.mouseLocation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let self else { return }
                guard Date().timeIntervalSince(self.lastStatusItemInteraction) > 0.12 else { return }
                if self.statusItemScreenFrame?.insetBy(dx: -4, dy: -4).contains(clickLocation) == true {
                    return
                }
                self.closePanel()
            }
        }
    }

    private var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button,
              let buttonWindow = button.window
        else { return nil }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(buttonRectInWindow)
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}

private struct QuotaPanel: View {
    @ObservedObject var model: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 8) {
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
        .padding(15)
        .modifier(GlassCardModifier())
        .padding(6)
        .frame(width: 276)
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
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private let edgeHighlight = LinearGradient(
        colors: [
            .white.opacity(0.52),
            .white.opacity(0.18),
            .white.opacity(0.08),
            .white.opacity(0.28),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white.opacity(0.07)), in: shape)
                .overlay {
                    shape.stroke(edgeHighlight, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.26), radius: 8, y: 3)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(edgeHighlight, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.26), radius: 8, y: 3)
        }
    }
}
