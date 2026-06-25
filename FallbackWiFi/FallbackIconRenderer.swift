import AppKit

enum FallbackIconRenderer {
    static func image(state: WiFiSwitcher.State, activeColor: NSColor) -> NSImage {
        let isActive = state.isFallbackActive
        let size = NSSize(width: 23, height: 22)
        let image = NSImage(size: size, flipped: true) { rect in
            draw(in: rect, color: isActive ? activeColor : .black, alpha: alpha(for: state))
            return true
        }
        image.isTemplate = !isActive
        return image
    }

    private static func alpha(for state: WiFiSwitcher.State) -> CGFloat {
        switch state {
        case .noBackupSelected, .disconnected:
            0.45
        case .switching:
            0.7
        case .error:
            0.85
        default:
            1
        }
    }

    private static func draw(in rect: NSRect, color: NSColor, alpha: CGFloat) {
        let scale = min(rect.width, rect.height) / 32
        let dx = rect.minX + (rect.width - (32 * scale)) / 2
        let dy = rect.minY + (rect.height - (32 * scale)) / 2

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: dx, yBy: dy)
        transform.scaleX(by: scale, yBy: scale)
        transform.concat()

        let iconColor = color.withAlphaComponent(alpha)
        iconColor.setStroke()
        iconColor.setFill()

        strokePath(lineWidth: 2.8) { path in
            path.move(to: NSPoint(x: 16, y: 5))
            path.line(to: NSPoint(x: 25, y: 9))
            path.line(to: NSPoint(x: 25, y: 15))
            path.curve(
                to: NSPoint(x: 16, y: 27),
                controlPoint1: NSPoint(x: 25, y: 21),
                controlPoint2: NSPoint(x: 21.2, y: 25)
            )
            path.curve(
                to: NSPoint(x: 7, y: 15),
                controlPoint1: NSPoint(x: 10.8, y: 25),
                controlPoint2: NSPoint(x: 7, y: 21)
            )
            path.line(to: NSPoint(x: 7, y: 9))
            path.close()
        }

        strokePath(lineWidth: 2.8) { path in
            path.move(to: NSPoint(x: 9.5, y: 14.5))
            path.curve(
                to: NSPoint(x: 22.5, y: 14.5),
                controlPoint1: NSPoint(x: 13.2, y: 11.6),
                controlPoint2: NSPoint(x: 18.8, y: 11.6)
            )
        }

        strokePath(lineWidth: 2.8) { path in
            path.move(to: NSPoint(x: 13, y: 18))
            path.curve(
                to: NSPoint(x: 19, y: 18),
                controlPoint1: NSPoint(x: 14.7, y: 16.7),
                controlPoint2: NSPoint(x: 17.3, y: 16.7)
            )
        }

        let dot = NSBezierPath(ovalIn: NSRect(x: 15.2, y: 21.2, width: 1.6, height: 1.6))
        dot.fill()

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func strokePath(lineWidth: CGFloat, build: (NSBezierPath) -> Void) {
        let path = NSBezierPath()
        build(path)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
