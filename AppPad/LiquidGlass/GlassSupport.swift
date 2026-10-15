import AppKit
import QuartzCore

// Shared helpers for the Liquid Glass controls (ported from YouMindHub GlassSegmentedControl).

// MARK: - GlassSpring

// Damped spring, same parameters as SwiftUI Spring(duration:bounce:) with mass 1.
// Semi-implicit Euler with 1/240 s sub-steps.
nonisolated struct GlassSpring {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0
    private var stiffness: CGFloat = 300
    private var damping: CGFloat = 30

    mutating func configure(_ s: (duration: Double, bounce: Double)) {
        stiffness = CGFloat(pow(2 * Double.pi / s.duration, 2))
        damping = CGFloat(4 * Double.pi * (1 - s.bounce) / s.duration)
    }

    mutating func snap(_ v: CGFloat) {
        value = v
        target = v
        velocity = 0
    }

    // Advances by dt; true once at rest on the target.
    mutating func step(_ dt: Double) -> Bool {
        var remaining = dt
        while remaining > 0 {
            let h = CGFloat(min(remaining, 1.0 / 240))
            let a = -stiffness * (value - target) - damping * velocity
            velocity += a * h
            value += velocity * h
            remaining -= Double(h)
        }
        if abs(value - target) < 0.0005, abs(velocity) < 0.0005 {
            value = target
            velocity = 0
            return true
        }
        return false
    }
}

// MARK: - HDR

// Extended-linear-sRGB white > 1.0 renders brighter than SDR white on EDR displays.
enum GlassHDR {
    static func white(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        if let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
           let c = CGColor(colorSpace: space, components: [value, value, value, alpha]) {
            return c
        }
        return NSColor.white.withAlphaComponent(alpha).cgColor
    }

    // EDR opt-in via KVC + float backing so values > 1 survive rasterization.
    static func enable(_ layer: CALayer) {
        if layer.responds(to: NSSelectorFromString("setWantsExtendedDynamicRangeContent:")) {
            layer.setValue(true, forKey: "wantsExtendedDynamicRangeContent")
        }
        layer.contentsFormat = .RGBA16Float
    }
}

// MARK: - Geometry

nonisolated func glassCapsulePath(_ r: CGRect) -> CGPath {
    let radius = max(0, min(r.width, r.height) / 2)
    return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Hermite 0 → 1 as x goes a → b (clamped).
nonisolated func glassSmoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

nonisolated func glassClamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
