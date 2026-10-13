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
            self.showGPU = store.bool(key: "dockLive_gpu", defaultValue: false)

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
        var (value, unit) = Units(bytes: bytes).getReadableTuple()
        if value.contains("."), let number = Double(value), number >= 10 {
            value = "\(Int(number.rounded()))"
        }
        return (value, String(unit.prefix(1)))
    }
}

private final class DockLiveView: NSView {
    typealias Speed = (value: String, unit: String)
    typealias Gauge = (title: String, value: Double)

    var network: (up: Speed, down: Speed)? = nil
    var cpu: Double? = nil
    var gpu: Double? = nil

    private let size: CGFloat = 128
    private let body = NSRect(x: 12.5, y: 12.5, width: 103, height: 103)

    private let upColor = NSColor(srgbRed: 0.93, green: 0.34, blue: 0.27, alpha: 1)
    private let downColor = NSColor(srgbRed: 0.24, green: 0.53, blue: 0.98, alpha: 1)
    private let secondary = NSColor(white: 1, alpha: 0.6)
    private let track = NSColor(white: 1, alpha: 0.12)

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        let scale = self.bounds.width / self.size
        context.scaleBy(x: scale, y: scale)
        defer { context.restoreGState() }

        var gauges: [Gauge] = []
        if let cpu = self.cpu { gauges.append(("CPU", cpu)) }
        if let gpu = self.gpu { gauges.append(("GPU", gpu)) }

        guard !gauges.isEmpty || self.network != nil else {
            NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: self.size, height: self.size))
            return
        }

        self.drawBackground(context)

        let content = self.body.insetBy(dx: 7, dy: 7)
        let row = NSRect(x: self.body.minX + 5, y: content.minY - 1, width: self.body.width - 10, height: 24)
        let top = NSRect(x: content.minX, y: row.maxY + 3, width: content.width, height: content.maxY - row.maxY - 3)

        switch (gauges.count, self.network) {
        case (0, let net?):
            self.drawNetworkStack(net, in: content.insetBy(dx: 0, dy: 4))
        case (1, nil):
            self.drawGauge(gauges[0], center: NSPoint(x: content.midX, y: content.midY + 2), radius: 32, line: 11, number: 38)
        case (_, nil):
            self.drawGaugeWithSide(gauges[0], gauges[1], in: content.insetBy(dx: 0, dy: 10))
        case (1, let net?):
            self.drawGauge(gauges[0], center: NSPoint(x: top.midX, y: top.midY + 2), radius: 25, line: 10, number: 30)
            self.drawNetworkRow(net, in: row)
        case (_, let net?):
            self.drawGaugeWithSide(gauges[0], gauges[1], in: top)
            self.drawNetworkRow(net, in: row)
        }
    }

    private func drawGaugeWithSide(_ main: Gauge, _ side: Gauge, in frame: NSRect) {
        let line: CGFloat = 9.5
        let radius = min(frame.height, 60) / 2 - line / 2
        let center = NSPoint(x: frame.minX + radius + line / 2, y: frame.midY + 2)
        self.drawGauge(main, center: center, radius: radius, line: line, number: radius * 1.15)

        let column = NSRect(x: center.x + radius + line / 2 + 2, y: frame.minY, width: frame.maxX - center.x - radius - line / 2 - 2, height: frame.height)
        let value = min(max(side.value, 0), 1)
        let label = NSAttributedString(string: side.title, attributes: [
            .font: self.font(13, .bold),
            .foregroundColor: self.secondary
        ])
        let number = self.fitted("\(Int((value*100).rounded()))", size: 24, width: column.width, color: self.color(value))
        let lsize = label.size(), nsize = number.size()
        let y = center.y - (lsize.height + nsize.height - 4) / 2
        number.draw(at: NSPoint(x: column.midX - nsize.width/2, y: y))
        label.draw(at: NSPoint(x: column.midX - lsize.width/2, y: y + nsize.height - 4))
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

    private func drawGauge(_ gauge: Gauge, center: NSPoint, radius: CGFloat, line: CGFloat, number: CGFloat) {
        let value = min(max(gauge.value, 0), 1)
        let start: CGFloat = 210, sweep: CGFloat = 240

        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
        trackPath.lineWidth = line
        trackPath.lineCapStyle = .round
        self.track.setStroke()
        trackPath.stroke()

        if value > 0.005 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep * CGFloat(value), clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            self.color(value).setStroke()
            arc.stroke()
        }

        let inner = (radius - line / 2) * 2 - 4
        let text = self.fitted("\(Int((value*100).rounded()))", size: number, width: inner, color: .white)
        let size = text.size()
        text.draw(at: NSPoint(x: center.x - size.width/2, y: center.y - size.height/2 + radius * 0.12))

        let label = NSAttributedString(string: gauge.title, attributes: [
            .font: self.font(13, .bold),
            .foregroundColor: self.secondary
        ])
        let lsize = label.size()
        label.draw(at: NSPoint(x: center.x - lsize.width/2, y: center.y - radius * 0.86 - lsize.height/2))
    }

    private func drawNetworkRow(_ net: (up: Speed, down: Speed), in frame: NSRect) {
        let gap: CGFloat = 7
        var size: CGFloat = 20
        while size > 13 && self.speedWidth(net.up, size: size) + self.speedWidth(net.down, size: size) + gap > frame.width {
            size -= 0.5
        }
        let up = self.speedWidth(net.up, size: size), down = self.speedWidth(net.down, size: size)
        let x = frame.midX - (up + gap + down) / 2
        self.drawSpeed(net.up, up: true, size: size, in: NSRect(x: x, y: frame.minY, width: up, height: frame.height))
        self.drawSpeed(net.down, up: false, size: size, in: NSRect(x: x + up + gap, y: frame.minY, width: down, height: frame.height))
    }

    private func drawNetworkStack(_ net: (up: Speed, down: Speed), in frame: NSRect) {
        let h = frame.height / 2
        self.drawSpeed(net.up, up: true, size: 28, in: NSRect(x: frame.minX, y: frame.midY + 1, width: frame.width, height: h))
        self.drawSpeed(net.down, up: false, size: 28, in: NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: h))

        let axis = NSRect(x: frame.minX + 4, y: frame.midY - 1, width: frame.width - 8, height: 2)
        self.upColor.setFill()
        NSRect(x: axis.minX, y: axis.midY, width: axis.width, height: axis.height/2).fill()
        self.downColor.setFill()
        NSRect(x: axis.minX, y: axis.minY, width: axis.width, height: axis.height/2).fill()
    }

    private func fit(_ speed: Speed, size: CGFloat, width: CGFloat) -> CGFloat {
        var size = size
        while size > 13 && self.speedWidth(speed, size: size) > width + 0.01 {
            size -= 0.5
        }
        return size
    }

    private func speedWidth(_ speed: Speed, size: CGFloat) -> CGFloat {
        return self.arrowWidth(size) + self.speedText(speed, size: size).size().width
    }

    private func arrowWidth(_ size: CGFloat) -> CGFloat {
        return size * 0.45 + 2
    }

    private func drawSpeed(_ speed: Speed, up: Bool, size: CGFloat, in frame: NSRect) {
        let size = self.fit(speed, size: size, width: frame.width)
        let text = self.speedText(speed, size: size)
        let s = text.size()
        let x = frame.midX - (self.arrowWidth(size) + s.width) / 2
        let y = frame.midY - s.height / 2
        text.draw(at: NSPoint(x: x + self.arrowWidth(size), y: y))

        let font = self.font(size, .bold)
        let w = size * 0.45, h = font.capHeight
        let base = y - font.descender
        let arrow = NSBezierPath()
        if up {
            arrow.move(to: NSPoint(x: x, y: base))
            arrow.line(to: NSPoint(x: x + w, y: base))
            arrow.line(to: NSPoint(x: x + w/2, y: base + h))
        } else {
            arrow.move(to: NSPoint(x: x, y: base + h))
            arrow.line(to: NSPoint(x: x + w, y: base + h))
            arrow.line(to: NSPoint(x: x + w/2, y: base))
        }
        arrow.close()
        (up ? self.upColor : self.downColor).setFill()
        arrow.fill()
    }

    private func speedText(_ speed: Speed, size: CGFloat) -> NSAttributedString {
        let text = NSMutableAttributedString(string: speed.value, attributes: [
            .font: self.font(size, .bold),
            .foregroundColor: NSColor.white,
            .kern: -0.3
        ])
        text.append(NSAttributedString(string: speed.unit, attributes: [
            .font: self.font(max(13, size * 0.65), .bold),
            .foregroundColor: self.secondary
        ]))
        return text
    }

    private func fitted(_ string: String, size: CGFloat, width: CGFloat, color: NSColor) -> NSAttributedString {
        var size = size
        var text: NSAttributedString
        repeat {
            text = NSAttributedString(string: string, attributes: [.font: self.font(size, .bold), .foregroundColor: color, .kern: -0.5])
            size -= 0.5
        } while text.size().width > width && size > 13
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
