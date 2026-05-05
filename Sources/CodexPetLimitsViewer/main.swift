import AppKit
import CodexPetLimitsViewerCore
import Foundation

final class LimitPopoverPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 228, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = LimitPopoverView()
    }

    func update(state: LimitState) {
        (contentView as? LimitPopoverView)?.state = state
    }
}

final class LimitPopoverView: NSView {
    var state: LimitState = .unavailable {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let body = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: body, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.06, alpha: 0.90).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.13).setStroke()
        path.lineWidth = 1
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.92)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.84)
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.55)
        ]

        "Codex Limits".draw(at: CGPoint(x: 14, y: 12), withAttributes: titleAttrs)
        state.fiveHour.displayLine.draw(at: CGPoint(x: 14, y: 36), withAttributes: bodyAttrs)
        state.weekly.displayLine.draw(at: CGPoint(x: 14, y: 56), withAttributes: bodyAttrs)

        let refreshed = Self.timeFormatter.string(from: state.refreshedAt)
        "\(state.source) - refreshed \(refreshed)".draw(at: CGPoint(x: 14, y: 84), withAttributes: metaAttrs)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

@main
final class CodexPetLimitsViewerApp: NSObject, NSApplicationDelegate {
    private let petReader = PetStateReader()
    private let limitReader = LimitStateReader()
    private let panel = LimitPopoverPanel()
    private var gate = HoverGate()
    private var timer: Timer?
    private var limitState = LimitState.unavailable
    private var lastRefresh = Date.distantPast
    private let panelSize = CGSize(width: 228, height: 112)

    static func main() {
        if CommandLine.arguments.contains("--once") {
            runOnce()
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            runDiagnose()
            return
        }

        let app = NSApplication.shared
        let delegate = CodexPetLimitsViewerApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshLimits(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        refreshLimits(force: false)

        guard let petFrame = petReader.readPetFrame(), let screen = screenContaining(petFrame) else {
            panel.orderOut(nil)
            _ = gate.update(now: Date().timeIntervalSince1970, pointer: NSEvent.mouseLocation, petFrame: nil, mouseDown: false)
            return
        }

        let shouldShow = gate.update(
            now: Date().timeIntervalSince1970,
            pointer: NSEvent.mouseLocation,
            petFrame: petFrame,
            mouseDown: NSEvent.pressedMouseButtons != 0
        )

        guard shouldShow else {
            panel.orderOut(nil)
            return
        }

        let origin = LimitPopoverPlacer.origin(for: panelSize, near: petFrame, in: screen.visibleFrame)
        panel.update(state: limitState)
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
        panel.orderFrontRegardless()
    }

    private func refreshLimits(force: Bool) {
        guard force || Date().timeIntervalSince(lastRefresh) > 60 else { return }
        lastRefresh = Date()
        limitReader.readCurrent { [weak self] state in
            DispatchQueue.main.async {
                self?.limitState = state
                self?.panel.update(state: state)
            }
        }
    }

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens
            .filter { $0.frame.intersects(rect) || $0.visibleFrame.intersects(rect) }
            .max { first, second in
                first.frame.intersection(rect).width * first.frame.intersection(rect).height
                    < second.frame.intersection(rect).width * second.frame.intersection(rect).height
            } ?? NSScreen.main
    }

    private static func runOnce() {
        let petFrame = PetStateReader().readPetFrame()
        if let petFrame {
            print("Pet frame: x=\(Int(petFrame.origin.x)) y=\(Int(petFrame.origin.y)) w=\(Int(petFrame.width)) h=\(Int(petFrame.height))")
        } else {
            print("Pet frame: unavailable")
        }

        let semaphore = DispatchSemaphore(value: 0)
        LimitStateReader().readCurrent { state in
            print(state.fiveHour.displayLine)
            print(state.weekly.displayLine)
            print("Source: \(state.source)")
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    private static func runDiagnose() {
        let reader = PetStateReader()
        let petFrame = reader.readPetFrame()
        print("Mouse: x=\(Int(NSEvent.mouseLocation.x)) y=\(Int(NSEvent.mouseLocation.y))")

        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            print("Screen \(index): frame x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height)) visible x=\(Int(visible.minX)) y=\(Int(visible.minY)) w=\(Int(visible.width)) h=\(Int(visible.height))")
        }

        guard let petFrame else {
            print("Pet frame: unavailable")
            return
        }

        print("Pet frame: x=\(Int(petFrame.minX)) y=\(Int(petFrame.minY)) w=\(Int(petFrame.width)) h=\(Int(petFrame.height))")
        let screen = NSScreen.screens
            .filter { $0.frame.intersects(petFrame) || $0.visibleFrame.intersects(petFrame) }
            .first ?? NSScreen.main
        if let screen {
            let origin = LimitPopoverPlacer.origin(
                for: CGSize(width: 228, height: 112),
                near: petFrame,
                in: screen.visibleFrame
            )
            print("Panel origin: x=\(Int(origin.x)) y=\(Int(origin.y)) on screen visibleFrame x=\(Int(screen.visibleFrame.minX)) y=\(Int(screen.visibleFrame.minY))")
        } else {
            print("Panel origin: no screen")
        }
    }
}
