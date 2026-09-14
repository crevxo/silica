import SwiftUI
import AppKit

/// Where the window's close / minimise / zoom buttons actually are, measured
/// from the window rather than assumed. macOS 27 draws them larger and further
/// in than earlier releases, and a hard-coded gap put the tab row on top of
/// them. Measured in window points from the top-left corner.
struct TrafficLightMetrics: Equatable {
    /// Right edge of the zoom button.
    var trailingEdge: CGFloat = 70
    /// Vertical centre of the buttons.
    var centerY: CGFloat = 19
}

private struct TrafficLightMetricsKey: EnvironmentKey {
    static let defaultValue = TrafficLightMetrics()
}

extension EnvironmentValues {
    var trafficLights: TrafficLightMetrics {
        get { self[TrafficLightMetricsKey.self] }
        set { self[TrafficLightMetricsKey.self] = newValue }
    }
}

/// A zero-size view that finds its window and reports the button frames. Re-reads
/// when the window resizes or goes full screen, since the buttons move.
struct TrafficLightReader: NSViewRepresentable {
    @Binding var metrics: TrafficLightMetrics

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { metrics = $0 }
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = { metrics = $0 }
    }

    final class ReaderView: NSView {
        var onChange: ((TrafficLightMetrics) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            AppDelegate.shared?.mainWindow = window
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.measure()
                })
            }
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let container = close.superview else { return }
            // Hidden in full screen; keep the last measurement rather than
            // collapsing the gap to nothing.
            guard !close.isHidden else { return }
            let closeFrame = container.convert(close.frame, to: nil)
            let zoomFrame = container.convert(zoom.frame, to: nil)
            let height = window.frame.height
            let metrics = TrafficLightMetrics(
                trailingEdge: zoomFrame.maxX,
                centerY: height - closeFrame.midY
            )
            onChange?(metrics)
        }
    }
}
