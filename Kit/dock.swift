//
//  dock.swift
//  Kit
//
//  Live data in the dock icon.
//
//  Using Swift 5.0
//  Running on macOS 14.3
//

import Cocoa

public final class DockLive {
    public static let shared = DockLive()

    private let interval: TimeInterval = 1
    private let view = DockLiveView()

    private var active: Bool = false
    private var showNet: Bool = true
    private var showCPU: Bool = true
    private var showGPU: Bool = true

    private var up: Int64? = nil
    private var down: Int64? = nil
    private var cpu: Double? = nil
    private var gpu: Double? = nil

    private var lastRefresh: Date = .distantPast
    private var pending: Bool = false

    private init() {}

    // Reads the settings and (un)installs the custom dock tile content.
    public func reload() {
        self.onMain {
            let store = Store.shared
            self.active = store.bool(key: "dockIcon", defaultValue: false) && store.bool(key: "dockLive", defaultValue: false)
            self.showNet = store.bool(key: "dockLive_net", defaultValue: true)
            self.showCPU = store.bool(key: "dockLive_cpu", defaultValue: true)
            self.showGPU = store.bool(key: "dockLive_gpu", defaultValue: true)

            let tile = NSApp.dockTile
            if self.active {
                self.view.frame = NSRect(origin: .zero, size: tile.size)
                tile.contentView = self.view
                self.refresh()
            } else {
                tile.contentView = nil
                tile.display()
            }
        }
    }

    public func setNetwork(up: Int64, down: Int64) {
        guard self.active && self.showNet else { return }
        self.onMain {
            self.up = up
            self.down = down
            self.schedule()
        }
    }

    public func setCPU(_ usage: Double) {
        guard self.active && self.showCPU else { return }
        self.onMain {
            self.cpu = usage
            self.schedule()
        }
    }

    public func setGPU(_ usage: Double) {
        guard self.active && self.showGPU else { return }
        self.onMain {
            self.gpu = usage
            self.schedule()
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func schedule() {
        guard self.active, !self.pending else { return }
        self.pending = true
        let delay = max(0, self.interval - Date().timeIntervalSince(self.lastRefresh))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pending = false
            self?.refresh()
        }
    }

    private func refresh() {
        guard self.active else { return }
        self.lastRefresh = Date()

        var rows: [DockLiveView.Row] = []
        if self.showNet, let up = self.up, let down = self.down {
            rows.append(.network(up: DockLive.speed(up), down: DockLive.speed(down)))
        }
        if self.showCPU, let cpu = self.cpu {
            rows.append(.bar(title: "CPU", value: cpu))
        }
        if self.showGPU, let gpu = self.gpu {
            rows.append(.bar(title: "GPU", value: gpu))
        }

        self.view.rows = rows
        self.view.needsDisplay = true
        NSApp.dockTile.display()
    }

    private static func speed(_ bytes: Int64) -> String {
        let (value, unit) = Units(bytes: bytes).getReadableTuple()
        return "\(value)\(unit.prefix(1))"
    }
}

private final class DockLiveView: NSView {
    enum Row {
        case network(up: String, down: String)
        case bar(title: String, value: Double)
    }

    var rows: [Row] = []

    private let size: CGFloat = 128
    private let rowHeight: CGFloat = 16
    private let margin: CGFloat = 10
    private let bottom: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        let scale = self.bounds.width / self.size
        context.scaleBy(x: scale, y: scale)
        defer { context.restoreGState() }

        NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: self.size, height: self.size))
        guard !self.rows.isEmpty else { return }

        let plate = NSRect(
            x: self.margin,
            y: self.bottom,
            width: self.size - self.margin*2,
            height: CGFloat(self.rows.count) * self.rowHeight + 8
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 9, yRadius: 9).fill()

        for (i, row) in self.rows.enumerated() {
            let y = plate.maxY - 4 - CGFloat(i+1) * self.rowHeight
            let frame = NSRect(x: plate.minX + 5, y: y, width: plate.width - 10, height: self.rowHeight)
            switch row {
            case .network(let up, let down):
                self.drawText("↑ \(up)  ↓ \(down)", in: frame, size: 10, weight: .semibold, alignment: .center)
            case .bar(let title, let value):
                self.drawBar(title, value: value, in: frame)
            }
        }
    }

    private func drawBar(_ title: String, value: Double, in frame: NSRect) {
        let value = min(max(value, 0), 1)

        self.drawText(title, in: NSRect(x: frame.minX, y: frame.minY, width: 28, height: frame.height), size: 9, weight: .bold, alignment: .left)
        self.drawText("\(Int(value*100))%", in: NSRect(x: frame.maxX - 28, y: frame.minY, width: 28, height: frame.height), size: 9, weight: .semibold, alignment: .right)

        let track = NSRect(x: frame.minX + 30, y: frame.midY - 3, width: frame.width - 60, height: 6)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()

        guard value > 0 else { return }
        var fill = track
        fill.size.width = max(track.height, track.width * CGFloat(value))
        let color: NSColor = value < 0.6 ? .systemGreen : (value < 0.85 ? .systemOrange : .systemRed)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }

    private func drawText(_ text: String, in frame: NSRect, size: CGFloat, weight: NSFont.Weight, alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ])
        let height = string.size().height
        string.draw(in: NSRect(x: frame.minX, y: frame.midY - height/2, width: frame.width, height: height))
    }
}
