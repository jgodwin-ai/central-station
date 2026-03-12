import AppKit
import CoreGraphics

enum AppIcon {
    static func generate() -> NSImage {
        // Try loading the bundled icon first
        if let bundled = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") {
            return bundled
        }
        return generateFallback()
    }

    static func generateFallback() -> NSImage {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Background: rounded square with dark blue gradient
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = 100
        let bgPath = CGPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Gradient background
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let colors = [
            CGColor(red: 0.1, green: 0.12, blue: 0.25, alpha: 1.0),
            CGColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1.0)
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])
        }
        ctx.restoreGState()

        // Train station roof (triangle/arch)
        ctx.saveGState()
        let roofColor = CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
        ctx.setFillColor(roofColor)
        ctx.move(to: CGPoint(x: size * 0.15, y: size * 0.45))
        ctx.addLine(to: CGPoint(x: size * 0.5, y: size * 0.85))
        ctx.addLine(to: CGPoint(x: size * 0.85, y: size * 0.45))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()

        // Station building (rectangle)
        ctx.saveGState()
        let buildingColor = CGColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 1.0)
        ctx.setFillColor(buildingColor)
        let buildingRect = CGRect(x: size * 0.18, y: size * 0.12, width: size * 0.64, height: size * 0.36)
        ctx.fill(buildingRect)
        ctx.restoreGState()

        // Clock face in the roof triangle
        let clockCenter = CGPoint(x: size * 0.5, y: size * 0.62)
        let clockRadius: CGFloat = size * 0.08
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.addArc(center: clockCenter, radius: clockRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()

        // Clock hands
        ctx.setStrokeColor(CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0))
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        // Hour hand (pointing to ~10)
        ctx.move(to: clockCenter)
        ctx.addLine(to: CGPoint(x: clockCenter.x - clockRadius * 0.4, y: clockCenter.y + clockRadius * 0.55))
        ctx.strokePath()
        // Minute hand (pointing to ~12)
        ctx.move(to: clockCenter)
        ctx.addLine(to: CGPoint(x: clockCenter.x, y: clockCenter.y + clockRadius * 0.7))
        ctx.strokePath()
        ctx.restoreGState()

        // Entrance arches (3 arches)
        let archColor = CGColor(red: 0.2, green: 0.22, blue: 0.35, alpha: 1.0)
        ctx.setFillColor(archColor)
        for i in 0..<3 {
            let archX = size * (0.25 + CGFloat(i) * 0.175)
            let archW: CGFloat = size * 0.12
            let archH: CGFloat = size * 0.2
            let archY: CGFloat = size * 0.12

            ctx.saveGState()
            let archPath = CGMutablePath()
            archPath.move(to: CGPoint(x: archX, y: archY))
            archPath.addLine(to: CGPoint(x: archX, y: archY + archH * 0.6))
            archPath.addArc(center: CGPoint(x: archX + archW/2, y: archY + archH * 0.6),
                           radius: archW/2, startAngle: .pi, endAngle: 0, clockwise: false)
            archPath.addLine(to: CGPoint(x: archX + archW, y: archY))
            archPath.closeSubpath()
            ctx.addPath(archPath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Columns (pillars between arches)
        ctx.setFillColor(CGColor(red: 0.75, green: 0.75, blue: 0.8, alpha: 1.0))
        for i in 0..<4 {
            let pillarX = size * (0.235 + CGFloat(i) * 0.175)
            ctx.fill(CGRect(x: pillarX, y: size * 0.12, width: size * 0.015, height: size * 0.33))
        }

        // Rail tracks at bottom
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 0.8))
        ctx.setLineWidth(3)
        // Two parallel rails
        for offset: CGFloat in [-12, 12] {
            ctx.move(to: CGPoint(x: size * 0.1, y: size * 0.08 + offset))
            ctx.addLine(to: CGPoint(x: size * 0.9, y: size * 0.08 + offset))
            ctx.strokePath()
        }
        // Rail ties
        ctx.setLineWidth(2)
        for i in 0..<12 {
            let x = size * (0.12 + CGFloat(i) * 0.065)
            ctx.move(to: CGPoint(x: x, y: size * 0.08 - 16))
            ctx.addLine(to: CGPoint(x: x, y: size * 0.08 + 16))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // "CS" text overlay
        ctx.saveGState()
        let textFont = CTFontCreateWithName("Helvetica-Bold" as CFString, size * 0.06, nil)
        let textColor = CGColor(red: 0.9, green: 0.85, blue: 0.4, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor(cgColor: textColor) ?? NSColor.white
        ]
        let str = NSAttributedString(string: "CLAUDE CENTRAL STATION", attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let textBounds = CTLineGetBoundsWithOptions(line, [])
        let textX = (size - textBounds.width) / 2
        ctx.textPosition = CGPoint(x: textX, y: size * 0.38)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        image.unlockFocus()
        return image
    }
}
