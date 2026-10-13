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

        if self.showNet, let up = self.up, let down = self.down {
            self.view.network = (DockLive.speed(up), DockLive.speed(down))
        } else {
            self.view.network = nil
        }
        self.view.cpu = self.showCPU ? self.cpu : nil
        self.view.gpu = self.showGPU ? self.gpu : nil

        self.view.needsDisplay = true
        NSApp.dockTile.display()
    }

    private static func speed(_ bytes: Int64) -> (value: String, unit: String) {
        let (value, unit) = Units(bytes: bytes).getReadableTuple()
        return (value, String(unit.prefix(1)))
    }
}

private final class DockLiveView: NSView {
    typealias Speed = (value: String, unit: String)

    var network: (up: Speed, down: Speed)? = nil
    var cpu: Double? = nil
    var gpu: Double? = nil

    private let size: CGFloat = 128
    private let body = NSRect(x: 12.5, y: 12.5, width: 103, height: 103)

    private let upColor = NSColor(srgbRed: 0.93, green: 0.34, blue: 0.27, alpha: 1)
    private let downColor = NSColor(srgbRed: 0.24, green: 0.53, blue: 0.98, alpha: 1)
    private let secondary = NSColor(white: 1, alpha: 0.55)
    private let track = NSColor(white: 1, alpha: 0.1)

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        let scale = self.bounds.width / self.size
        context.scaleBy(x: scale, y: scale)
        defer { context.restoreGState() }

        var gauges: [(String, Double)] = []
        if let cpu = self.cpu { gauges.append(("CPU", cpu)) }
        if let gpu = self.gpu { gauges.append(("GPU", gpu)) }

        guard !gauges.isEmpty || self.network != nil else {
            NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: self.size, height: self.size))
            return
        }

        self.drawBackground(context)

        let content = self.body.insetBy(dx: 8, dy: 8)
        let netRow = NSRect(x: content.minX, y: content.minY + 1, width: content.width, height: 22)
        switch (gauges.count, self.network) {
        case (0, let net?):
            self.drawNetworkStack(net, in: content.insetBy(dx: 0, dy: 4))
        case (1, nil):
            self.drawGauge(gauges[0], center: NSPoint(x: content.midX, y: content.midY + 2), radius: 32, number: 32)
        case (2, nil):
            self.drawGaugePair(gauges, y: content.midY + 2, in: content)
        case (1, let net?):
            self.drawGauge(gauges[0], center: NSPoint(x: content.midX, y: content.maxY - 27), radius: 25, number: 26)
            self.drawNetworkRow(net, in: netRow)
        case (_, let net?):
            self.drawGaugePair(gauges, y: content.maxY - 24, in: content)
            self.drawNetworkRow(net, in: netRow)
        default:
            break
        }
    }

    private func drawGaugePair(_ gauges: [(String, Double)], y: CGFloat, in frame: NSRect) {
        let offset: CGFloat = 22
        self.drawGauge(gauges[0], center: NSPoint(x: frame.midX - offset, y: y), radius: 17.5, number: 18)
        self.drawGauge(gauges[1], center: NSPoint(x: frame.midX + offset, y: y), radius: 17.5, number: 18)
    }

    private func squircle(_ rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let n: CGFloat = 5
        let a = rect.width/2, b = rect.height/2
        for i in 0..<240 {
            let t = CGFloat(i) / 240 * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2/n)
            let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2/n)
            i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
        }
        path.close()
        return path
    }

    private func drawBackground(_ context: CGContext) {
        let shape = self.squircle(self.body)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 4, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(white: 0.18, alpha: 1).setFill()
        shape.fill()
        context.restoreGState()

        context.saveGState()
        shape.addClip()
        NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.25, alpha: 1),
                   ending: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1))?.draw(in: self.body, angle: -90)

        NSColor(white: 1, alpha: 0.035).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        var p = self.body.minX + 12.875
        while p < self.body.maxX {
            grid.move(to: NSPoint(x: p, y: self.body.minY))
            grid.line(to: NSPoint(x: p, y: self.body.maxY))
            grid.move(to: NSPoint(x: self.body.minX, y: p))
            grid.line(to: NSPoint(x: self.body.maxX, y: p))
            p += 12.875
        }
        grid.stroke()
        context.restoreGState()

        let rim = self.squircle(self.body.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        context.saveGState()
        rim.addClip()
        NSGradient(starting: NSColor(white: 1, alpha: 0.22), ending: NSColor(white: 1, alpha: 0.03))?.draw(in: self.body, angle: -90)
        context.restoreGState()
        NSColor(white: 0, alpha: 0.4).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }

    private func drawGauge(_ gauge: (title: String, value: Double), center: NSPoint, radius: CGFloat, number: CGFloat) {
        let value = min(max(gauge.value, 0), 1)
        let width = max(4, radius * 0.19)
        let start: CGFloat = 225, sweep: CGFloat = 270

        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
        trackPath.lineWidth = width
        trackPath.lineCapStyle = .round
        self.track.setStroke()
        trackPath.stroke()

        if value > 0.005 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep * CGFloat(value), clockwise: true)
            arc.lineWidth = width
            arc.lineCapStyle = .round
            self.color(value).setStroke()
            arc.stroke()
        }

        let digits = "\(Int((value*100).rounded()))"
        var number = number
        var text: NSAttributedString
        repeat {
            text = NSAttributedString(string: digits, attributes: [.font: self.font(number, .bold), .foregroundColor: NSColor.white])
            number -= 0.5
        } while text.size().width > radius * 1.5 && number > 11
        let size = text.size()
        text.draw(at: NSPoint(x: center.x - size.width/2, y: center.y - size.height/2 + 1))

        let label = NSAttributedString(string: gauge.title, attributes: [
            .font: self.font(11, .bold),
            .foregroundColor: self.secondary,
            .kern: 0.4
        ])
        let lsize = label.size()
        label.draw(at: NSPoint(x: center.x - lsize.width/2, y: center.y - radius - lsize.height/2 + 1))
    }

    private func drawNetworkRow(_ net: (up: Speed, down: Speed), in frame: NSRect) {
        let column = frame.width / 2 - 3
        let size = min(self.fit(net.up, size: 17, width: column), self.fit(net.down, size: 17, width: column))
        self.drawSpeed(net.up, arrow: "↑", color: self.upColor, size: size, in: NSRect(x: frame.minX, y: frame.minY, width: column, height: frame.height))
        self.drawSpeed(net.down, arrow: "↓", color: self.downColor, size: size, in: NSRect(x: frame.maxX - column, y: frame.minY, width: column, height: frame.height))

        NSColor(white: 1, alpha: 0.08).setFill()
        NSRect(x: frame.minX + 6, y: frame.maxY + 3, width: frame.width - 12, height: 1).fill()
    }

    private func drawNetworkStack(_ net: (up: Speed, down: Speed), in frame: NSRect) {
        let h = frame.height / 2
        self.drawSpeed(net.up, arrow: "↑", color: self.upColor, size: 26, in: NSRect(x: frame.minX, y: frame.midY, width: frame.width, height: h))
        self.drawSpeed(net.down, arrow: "↓", color: self.downColor, size: 26, in: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: h))

        let axis = NSRect(x: frame.minX + 4, y: frame.midY - 0.75, width: frame.width - 8, height: 1.5)
        self.upColor.withAlphaComponent(0.8).setFill()
        NSRect(x: axis.minX, y: axis.midY, width: axis.width, height: axis.height/2).fill()
        self.downColor.withAlphaComponent(0.8).setFill()
        NSRect(x: axis.minX, y: axis.minY, width: axis.width, height: axis.height/2).fill()
    }

    private func fit(_ speed: Speed, size: CGFloat, width: CGFloat) -> CGFloat {
        var size = size
        while size > 12 && self.speedText(speed, arrow: "↑", color: .white, size: size).size().width > width {
            size -= 0.5
        }
        return size
    }

    private func drawSpeed(_ speed: Speed, arrow: String, color: NSColor, size: CGFloat, in frame: NSRect) {
        let text = self.speedText(speed, arrow: arrow, color: color, size: self.fit(speed, size: size, width: frame.width))
        let s = text.size()
        text.draw(at: NSPoint(x: frame.midX - s.width/2, y: frame.midY - s.height/2))
    }

    private func speedText(_ speed: Speed, arrow: String, color: NSColor, size: CGFloat) -> NSAttributedString {
        let text = NSMutableAttributedString(string: arrow, attributes: [
            .font: self.font(size * 0.8, .heavy),
            .foregroundColor: color
        ])
        text.append(NSAttributedString(string: speed.value, attributes: [
            .font: self.font(size, .bold),
            .foregroundColor: NSColor.white
        ]))
        text.append(NSAttributedString(string: speed.unit, attributes: [
            .font: self.font(max(11, size * 0.62), .semibold),
            .foregroundColor: self.secondary
        ]))
        return text
    }

    private func color(_ value: Double) -> NSColor {
        if value < 0.6 { return NSColor(srgbRed: 0.2, green: 0.84, blue: 0.45, alpha: 1) }
        if value < 0.85 { return NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1) }
        return NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)
    }

    private func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
