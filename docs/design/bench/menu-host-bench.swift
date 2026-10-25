// Menu card hosting bench (design phase, not shipped).
//
// Compares the footprint of hosting one provider card as four NSHostingViews (one per section, today's
// shape) against one NSHostingView with the same content, and against static CoreGraphics meters.
// Runs offscreen in its own accessory process: no OpenBar launch, no Keychain, no network.
//
//   swiftc -O -parse-as-library docs/design/bench/menu-host-bench.swift -o /tmp/menu-host-bench
//   /tmp/menu-host-bench <split|single|single-static|single-nometer> <cards>
import AppKit
import SwiftUI

@MainActor
func footprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576
}

/// SwiftUI shape meter: one view per track/fill, like a naive implementation.
struct ShapeMeter: View {
    let fraction: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.orange).frame(width: proxy.size.width * self.fraction)
            }
        }
        .frame(height: 6)
    }
}

/// Static meter: one CGImage drawn once per value.
struct StaticMeter: View {
    let fraction: Double
    var body: some View {
        Image(decorative: Self.image(self.fraction), scale: 2).frame(height: 6)
    }

    static func image(_ fraction: Double) -> CGImage {
        let width = 560, height = 12
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.gray.withAlphaComponent(0.2).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                               cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor.orange.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: Double(width) * fraction, height: Double(height)),
                               cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()
        return context.makeImage()!
    }
}

struct Lane: View {
    nonisolated(unsafe) static var omitsMeter = false
    let title: String
    let fraction: Double
    let staticMeter: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(self.fraction * 100))% left").font(.system(size: 13).monospacedDigit())
            }
            if Lane.omitsMeter {
                Color.clear.frame(height: 6)
            } else if self.staticMeter {
                StaticMeter(fraction: self.fraction)
            } else {
                ShapeMeter(fraction: self.fraction)
            }
            Text("Resets in 3h 12m").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("Synthetic").font(.headline); Spacer(); Text("Pro").font(.footnote) }
            Text("Updated just now").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct Section1: View {
    let staticMeter: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header()
            Divider()
            Lane(title: "Session", fraction: 0.62, staticMeter: self.staticMeter)
            Lane(title: "Weekly", fraction: 0.41, staticMeter: self.staticMeter)
        }.padding(.horizontal, 14).padding(.vertical, 8).frame(width: 300)
    }
}

struct Section2: View {
    let staticMeter: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Lane(title: "Credits", fraction: 0.8, staticMeter: self.staticMeter)
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(width: 300)
    }
}

struct Section3: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cost").font(.system(size: 13, weight: .semibold))
            Text("Today: $4.12 · 1.2M tokens").font(.footnote)
            Text("Last 30 days: $88.40 · 31M tokens").font(.footnote)
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(width: 300, alignment: .leading)
    }
}

struct Combined: View {
    let staticMeter: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Section1(staticMeter: self.staticMeter)
            Divider().padding(.horizontal, 14)
            Section2(staticMeter: self.staticMeter)
            Divider().padding(.horizontal, 14)
            Lane(title: "Extra usage", fraction: 0.1, staticMeter: self.staticMeter)
                .padding(.horizontal, 14).padding(.vertical, 6).frame(width: 300)
            Divider().padding(.horizontal, 14)
            Section3()
        }
    }
}

final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class Bench: NSObject, NSApplicationDelegate {
    let variant: String
    let cards: Int
    var window: NSWindow?

    init(variant: String, cards: Int) {
        self.variant = variant
        self.cards = cards
    }

    func pump(_ seconds: Double) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: min(until, Date().addingTimeInterval(0.05)))
            self.window?.displayIfNeeded()
        }
    }

    func hostingViews() -> [NSView] {
        let staticMeter = self.variant == "single-static"
        if self.variant == "split" {
            return [
                NSHostingView(rootView: Section1(staticMeter: false)),
                NSHostingView(rootView: Section2(staticMeter: false)),
                NSHostingView(rootView: Lane(title: "Extra usage", fraction: 0.1, staticMeter: false)
                    .padding(.horizontal, 14).padding(.vertical, 6).frame(width: 300)),
                NSHostingView(rootView: Section3()),
            ]
        }
        return [NSHostingView(rootView: Combined(staticMeter: staticMeter))]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = OffscreenWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 2000),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        window.contentView = stack
        window.orderFrontRegardless()
        self.window = window
        // Warm SwiftUI once so the first-use runtime cost is excluded from the per-card numbers.
        let warm = NSHostingView(rootView: Section3())
        stack.addArrangedSubview(warm)
        self.pump(1.0)
        warm.removeFromSuperview()
        self.pump(0.5)
        let before = footprintMiB()
        var hosts = 0
        for _ in 0..<self.cards {
            for view in self.hostingViews() {
                stack.addArrangedSubview(view)
                hosts += 1
            }
        }
        self.pump(2.0)
        let after = footprintMiB()
        let perCard = (after - before) / Double(self.cards) * 1024
        print(String(
            format: "{\"variant\": \"%@\", \"cards\": %d, \"hosts\": %d, \"delta_mib\": %.1f, \"per_card_kib\": %.0f}",
            self.variant, self.cards, hosts, after - before, perCard))
        fflush(stdout)
        exit(0)
    }
}

@main
enum Main {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3, let cards = Int(arguments[2]) else {
            print("usage: menu-host-bench <split|single|single-static|single-nometer> <cards>")
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Lane.omitsMeter = arguments[1] == "single-nometer"
        let bench = Bench(variant: arguments[1], cards: cards)
        app.delegate = bench
        withExtendedLifetime(bench) { app.run() }
    }
}
