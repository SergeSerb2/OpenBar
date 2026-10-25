import AppKit
import OpenBarCore
import QuartzCore

@MainActor
final class ScreenConfettiOverlayController {
    static let overlayLifetime: TimeInterval = 8.5

    private let logger = OpenBarLog.logger(LogCategories.confetti)
    private var windows: [NSWindow] = []
    private var dismissalTask: Task<Void, Never>?

    func play(originInScreen origin: CGPoint?, colors: [ProviderColor]) {
        // Reduce Motion skips the celebration entirely (docs/design/README.md §7, §10).
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.logger.debug("Skipping confetti because Reduce Motion is on")
            return
        }
        guard self.windows.isEmpty else {
            self.logger.debug("Ignoring confetti trigger while overlay is already active")
            return
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            self.logger.error("Cannot present confetti overlay because no screens were found")
            return
        }

        let palette = colors.map { color in
            CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
        let startTime = CACurrentMediaTime()
        self.windows = screens.map { screen in
            let frame = screen.frame
            let fireworks = ScreenConfettiFireworks(origin: Self.localOrigin(in: frame, from: origin), colors: palette)
            // Layer-hosting view: AppKit draws nothing into it; the emitter layers hold all content.
            let contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
            contentView.layer = CALayer()
            contentView.wantsLayer = true
            for emitter in fireworks.makeEmitterLayers(in: frame.size, contentsScale: screen.backingScaleFactor) {
                emitter.beginTime = startTime
                contentView.layer?.addSublayer(emitter)
            }

            let window = ClickThroughOverlayPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen)
            window.contentView = contentView
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.acceptsMouseMovedEvents = false
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.canHide = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.isExcludedFromWindowsMenu = true
            window.setFrame(frame, display: false)
            return window
        }

        self.logger.info(
            "Presenting confetti overlay",
            metadata: [
                "screenCount": "\(self.windows.count)",
                "originKnown": origin == nil ? "0" : "1",
            ])

        for window in self.windows {
            window.orderFrontRegardless()
        }

        self.dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.overlayLifetime))
            self?.dismiss()
        }
    }

    func dismiss() {
        self.dismissalTask?.cancel()
        self.dismissalTask = nil

        guard !self.windows.isEmpty else { return }
        for window in self.windows {
            window.orderOut(nil)
            window.close()
        }
        self.windows.removeAll(keepingCapacity: true)
    }

    private static func localOrigin(in screenFrame: CGRect, from globalOrigin: CGPoint?) -> CGPoint {
        let fallback = CGPoint(x: screenFrame.maxX - 28, y: screenFrame.maxY - 8)
        let resolved: CGPoint = if let globalOrigin, screenFrame.contains(globalOrigin) {
            globalOrigin
        } else {
            fallback
        }

        let insetFrame = screenFrame.insetBy(dx: 8, dy: 8)
        return CGPoint(
            x: min(max(resolved.x, insetFrame.minX), insetFrame.maxX) - screenFrame.minX,
            y: min(max(resolved.y, insetFrame.minY), insetFrame.maxY) - screenFrame.minY)
    }
}

private final class ClickThroughOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

/// Fireworks drawn with Core Animation particles. Canvas-based particle views render through RenderBox's
/// Metal backend on macOS 26+, which commits ~97 MB of graphics memory in the app while they play.
///
/// Each side of the origin fans six launch angles out 60 ms apart. Every phase fires three tracers that
/// burst into 42 confetti pieces just before they expire. Speeds and accelerations are in screen heights
/// per second, and y points up.
struct ScreenConfettiFireworks {
    private static let clockwiseLaunchAngles: [Double] = [270, 234, 198, 162, 126, 90]
    private static let phaseInterval: CFTimeInterval = 0.06
    private static let tracerRate: Float = 18
    private static let tracerScale: CGFloat = 0.34
    private static let tracerScaleAtBurst: CGFloat = 0.4
    private static let piecesPerBurst = 42
    private static let pieceRate: Float = 60
    /// Core Animation particles have no drag; trimming confetti speeds and gravity stands in for light air drag.
    private static let dragCompensation: CGFloat = 0.97

    let origin: CGPoint
    let colors: [CGColor]

    /// One emitter layer per launch. When a layer has several cells with sub-cells, Core Animation draws
    /// the particles of every cell after the first with another cell's image.
    func makeEmitterLayers(in size: CGSize, contentsScale: CGFloat) -> [CAEmitterLayer] {
        let sprites = ScreenConfettiSprites(contentsScale: contentsScale)
        let sides: [(lateralOffset: CGFloat, angles: [Double])] = [
            (-12, Self.clockwiseLaunchAngles),
            (12, Self.clockwiseLaunchAngles.reversed()),
        ]
        return sides.flatMap { side in
            side.angles.enumerated().map { phaseIndex, angle in
                let emitter = CAEmitterLayer()
                emitter.frame = CGRect(origin: .zero, size: size)
                emitter.emitterShape = .point
                emitter.emitterPosition = self.launchPoint(in: size, lateralOffset: side.lateralOffset)
                emitter.seed = UInt32.random(in: 0...UInt32.max)
                emitter.emitterCells = [
                    self.makeTracerCell(in: size, launchAngle: angle, phaseIndex: phaseIndex, sprites: sprites),
                ]
                return emitter
            }
        }
    }

    /// `launchAngle` is in degrees clockwise from straight up.
    private func makeTracerCell(
        in size: CGSize,
        launchAngle: Double,
        phaseIndex: Int,
        sprites: ScreenConfettiSprites)
        -> CAEmitterCell
    {
        let height = size.height
        let lifetime = 0.58 + Float(phaseIndex) * 0.03
        let tracer = CAEmitterCell()
        tracer.contents = sprites.tracer
        tracer.contentsScale = sprites.contentsScale
        // A cell with a positive begin time emits its first particle at that time, then one every
        // 1 / birthRate seconds until its duration ends.
        tracer.beginTime = Double(phaseIndex) * Self.phaseInterval + 1 / Double(Self.tracerRate)
        tracer.birthRate = Self.tracerRate
        tracer.duration = 2.5 / Double(Self.tracerRate)
        tracer.lifetime = lifetime
        tracer.velocity = (1.36 + CGFloat(phaseIndex) * 0.04) * height
        tracer.velocityRange = 0.12 * height
        tracer.emissionLongitude = (90 - launchAngle) * .pi / 180
        tracer.emissionRange = 6 * .pi / 180
        tracer.yAcceleration = -0.12 * height
        tracer.scale = Self.tracerScale
        tracer.scaleSpeed = -Self.tracerScale * (1 - Self.tracerScaleAtBurst) / CGFloat(lifetime)
        tracer.spin = -6
        tracer.spinRange = 8

        // Child cells time their emission from the tracer's birth. Half an interval emits exactly one piece
        // per cell, just before the tracer expires. Pieces inherit the tracer's current scale.
        let burstAge = Double(lifetime) - 0.5 / Double(Self.pieceRate)
        let inheritedScale = Self.tracerScale
            * (1 - (1 - Self.tracerScaleAtBurst) * CGFloat(burstAge / Double(lifetime)))
        let sectorWidth = 2 * CGFloat.pi / CGFloat(Self.piecesPerBurst)
        tracer.emitterCells = (0..<Self.piecesPerBurst).map { index in
            let piece = CAEmitterCell()
            piece.contents = sprites.pieces.randomElement()
            piece.contentsScale = sprites.contentsScale
            piece.color = self.colors.randomElement() ?? CGColor(gray: 1, alpha: 1)
            piece.beginTime = burstAge
            piece.birthRate = Self.pieceRate
            piece.duration = 0.5 / Double(Self.pieceRate)
            piece.lifetime = 8
            piece.velocity = 0.72 * height * Self.dragCompensation
            piece.velocityRange = 0.44 * height * Self.dragCompensation
            // One direction per cell keeps the burst a flat ring; a wide emission cone would scatter
            // pieces in 3D and fill the ring in.
            piece.emissionLongitude = (CGFloat(index) + .random(in: 0..<1)) * sectorWidth
            piece.emissionRange = sectorWidth / 2
            piece.yAcceleration = -0.32 * height * Self.dragCompensation
            piece.scale = 0.74 / inheritedScale
            piece.scaleRange = 0.26 / inheritedScale
            piece.spin = -3
            piece.spinRange = 14
            return piece
        }
        return tracer
    }

    private func launchPoint(in size: CGSize, lateralOffset: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(self.origin.x + lateralOffset, 0), size.width),
            y: min(max(self.origin.y - 18, 0), size.height))
    }
}

/// White particle images in points; emitter cells tint them with the palette.
private struct ScreenConfettiSprites {
    let contentsScale: CGFloat
    let tracer: CGImage?
    let pieces: [CGImage]

    init(contentsScale: CGFloat) {
        self.contentsScale = contentsScale
        // A soft glow; tracers draw it at about a third of its size.
        self.tracer = Self.image(CGSize(width: 15, height: 15), scale: contentsScale) { context, bounds in
            let core = CGColor(gray: 1, alpha: 0.9)
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [core, core, CGColor(gray: 1, alpha: 0)] as CFArray,
                locations: [0, 0.2, 1])
            if let gradient {
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: bounds.width / 2,
                    options: [])
            }
        }
        let bar = Self.image(CGSize(width: 10, height: 20), scale: contentsScale) { context, bounds in
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.fillPath()
        }
        let dot = Self.image(CGSize(width: 9, height: 9), scale: contentsScale) { context, bounds in
            context.fillEllipse(in: bounds)
        }
        // An 8 x 16 pt capsule tilted 30 degrees.
        let pill = Self.image(CGSize(width: 16, height: 18), scale: contentsScale) { context, bounds in
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: -.pi / 6)
            let capsule = CGRect(x: -4, y: -8, width: 8, height: 16)
            context.addPath(CGPath(roundedRect: capsule, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.fillPath()
        }
        self.pieces = [bar, dot, pill].compactMap(\.self)
    }

    private static func image(
        _ size: CGSize,
        scale: CGFloat,
        draw: (CGContext, CGRect) -> Void)
        -> CGImage?
    {
        guard let context = CGContext(
            data: nil,
            width: Int((size.width * scale).rounded(.up)),
            height: Int((size.height * scale).rounded(.up)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        draw(context, CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
