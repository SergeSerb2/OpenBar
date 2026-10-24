import QuartzCore
import Testing
@testable import OpenBar

@MainActor
struct ScreenConfettiLifetimeTests {
    @Test
    func `upward confetti clears the screen before particle and overlay expiry`() throws {
        let size = CGSize(width: 1000, height: 1000)
        let fireworks = ScreenConfettiFireworks(origin: CGPoint(x: 500, y: 1000), colors: [])
        let emitters = fireworks.makeEmitterLayers(in: size, contentsScale: 2)
        #expect(emitters.count == 12)
        for (index, emitter) in emitters.enumerated() {
            let tracer = try #require(emitter.emitterCells?.first)
            let confetti = try #require(tracer.emitterCells?.first)
            // Use the highest possible launch and fastest upward fragment. Core Animation integrates
            // constant acceleration without drag, in points with y up.
            let offAxis = abs(remainder(Double(tracer.emissionLongitude) - .pi / 2, 2 * .pi))
            let closestToUp = max(offAxis - Double(tracer.emissionRange), 0)
            let speedSpread = Double(tracer.velocityRange) / 2
            let launchSpeed = Double(tracer.velocity) + (cos(closestToUp) >= 0 ? speedSpread : -speedSpread)
            let lifetime = Double(tracer.lifetime)
            let burstY = Double(emitter.emitterPosition.y) + cos(closestToUp) * launchSpeed * lifetime
                + Double(tracer.yAcceleration) * lifetime * lifetime / 2
            let upwardSpeed = Double(confetti.velocity + confetti.velocityRange / 2)
            let gravity = -Double(confetti.yAcceleration)
            let drop = burstY + 0.02 * size.height
            let fallTime = (upwardSpeed + (upwardSpeed * upwardSpeed + 2 * gravity * drop).squareRoot()) / gravity
            #expect(fallTime < Double(confetti.lifetime), "Emitter \(index) expires before clearing the bottom edge")
            let lastExit = tracer.beginTime + tracer.duration + lifetime + fallTime
            #expect(lastExit < ScreenConfettiOverlayController.overlayLifetime)
        }
    }
}
