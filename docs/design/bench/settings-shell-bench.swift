// Settings shell memory bench (design phase, not shipped).
//
// Measures the process footprint cost of four Settings window shells that host the same synthetic
// content: 11 app panes plus 109 provider rows that load the real provider SVGs, and a grouped Form
// detail. Runs as its own accessory process with an offscreen window: no OpenBar launch, no Keychain,
// no network.
//
//   swiftc -O -parse-as-library docs/design/bench/settings-shell-bench.swift -o /tmp/settings-shell-bench
//   /tmp/settings-shell-bench <nsv|hstack|appkit-split|tabs> <repo-root>
//
// Prints one JSON line with phys_footprint (MiB) at each phase.
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

enum Pane: Hashable {
    case app(Int)
    case provider(String)
}

@MainActor
@Observable
final class BenchSelection {
    var pane: Pane = .app(0)
    var search = ""
}

let appPanes: [(String, String, Color)] = [
    ("General", "gearshape.fill", .gray), ("iCloud Sync", "icloud.fill", .blue),
    ("Usage & Spend", "chart.bar.fill", .green), ("Notifications", "bell.badge.fill", .red),
    ("Menu Bar", "menubar.rectangle", .blue), ("Menu", "filemenu.and.selection", .teal),
    ("Advanced", "slider.horizontal.3", .purple), ("Hooks", "bolt.horizontal.circle.fill", .orange),
    ("Plugins", "puzzlepiece.extension.fill", .indigo), ("About", "info.circle.fill", .green),
    ("Debug", "ladybug.fill", .red),
]

@MainActor
final class ProviderIcons {
    static var root = ""
    static let names: [String] = {
        let dir = URL(fileURLWithPath: root).appendingPathComponent("Sources/OpenBar/Resources")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasPrefix("ProviderIcon-") && $0.hasSuffix(".svg") }.sorted()
    }()

    static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let cached = self.cache[name] { return cached }
        let url = URL(fileURLWithPath: root).appendingPathComponent("Sources/OpenBar/Resources/\(name)")
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        self.cache[name] = image
        return image
    }
}

struct IconChip: View {
    let systemImage: String
    let color: Color
    var body: some View {
        Image(systemName: self.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(self.color.gradient))
    }
}

struct SidebarList: View {
    @Bindable var selection: BenchSelection
    var body: some View {
        List(selection: self.$selection.pane) {
            Section {
                ForEach(Array(appPanes.enumerated()), id: \.offset) { index, pane in
                    HStack(spacing: 8) {
                        IconChip(systemImage: pane.1, color: pane.2)
                        Text(pane.0)
                    }
                    .tag(Pane.app(index))
                }
            }
            Section("Providers") {
                ForEach(ProviderIcons.names.filter {
                    self.selection.search.isEmpty || $0.localizedCaseInsensitiveContains(self.selection.search)
                }, id: \.self) { name in
                    HStack(spacing: 8) {
                        if let image = ProviderIcons.image(name) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
                        }
                        Text(name.dropFirst("ProviderIcon-".count).dropLast(4).capitalized)
                        Spacer()
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                    .tag(Pane.provider(name))
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct DetailForm: View {
    let pane: Pane
    @State private var toggles = Array(repeating: true, count: 8)
    @State private var choice = 1
    @State private var text = "synthetic"
    var body: some View {
        Form {
            Section("Display") {
                ForEach(0..<4, id: \.self) { index in
                    Toggle("Synthetic option \(index)", isOn: self.$toggles[index])
                }
                Picker("Style", selection: self.$choice) {
                    Text("Percent").tag(0)
                    Text("Pace").tag(1)
                    Text("Both").tag(2)
                }
            }
            Section("Behavior") {
                ForEach(4..<8, id: \.self) { index in
                    Toggle("Synthetic option \(index)", isOn: self.$toggles[index])
                }
                TextField("Label", text: self.$text)
                LabeledContent("Version", value: "1.0.0")
            }
        }
        .formStyle(.grouped)
        .id(self.pane)
    }
}

struct NSVRoot: View {
    @Bindable var selection: BenchSelection
    var body: some View {
        NavigationSplitView {
            SidebarList(selection: self.selection)
                .searchable(text: self.$selection.search, placement: .sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 380)
        } detail: {
            DetailForm(pane: self.selection.pane)
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HStack {
                            Button {} label: { Image(systemName: "chevron.backward") }
                            Button {} label: { Image(systemName: "chevron.forward") }
                        }
                    }
                }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search providers", text: self.$text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct HStackRoot: View {
    @Bindable var selection: BenchSelection
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                SearchField(text: self.$selection.search)
                SidebarList(selection: self.selection).scrollContentBackground(.hidden)
            }
            .frame(width: 260)
            .background { SidebarMaterial().ignoresSafeArea() }
            Divider().ignoresSafeArea()
            DetailForm(pane: self.selection.pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct SidebarOnly: View {
    @Bindable var selection: BenchSelection
    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: self.$selection.search)
            SidebarList(selection: self.selection)
        }
    }
}

struct DetailOnly: View {
    @Bindable var selection: BenchSelection
    var body: some View {
        DetailForm(pane: self.selection.pane)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    let selection = BenchSelection()
    var window: NSWindow?
    var samples: [String: Double] = [:]

    init(variant: String) {
        self.variant = variant
    }

    func makeContentController() -> NSViewController {
        switch self.variant {
        case "nsv":
            return NSHostingController(rootView: NSVRoot(selection: self.selection))
        case "hstack":
            return NSHostingController(rootView: HStackRoot(selection: self.selection))
        case "appkit-split":
            let split = NSSplitViewController()
            let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(
                rootView: SidebarOnly(selection: self.selection)))
            sidebar.minimumThickness = 200
            sidebar.maximumThickness = 380
            split.addSplitViewItem(sidebar)
            split.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(
                rootView: DetailOnly(selection: self.selection))))
            return split
        case "tabs":
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for (index, pane) in appPanes.prefix(10).enumerated() {
                let controller: NSViewController = if index == 4 {
                    NSHostingController(rootView: HStackRoot(selection: self.selection))
                } else {
                    NSHostingController(rootView: DetailForm(pane: .app(index)))
                }
                let item = NSTabViewItem(viewController: controller)
                item.label = pane.0
                item.image = NSImage(systemSymbolName: pane.1, accessibilityDescription: nil)
                tabs.addTabViewItem(item)
            }
            return tabs
        default:
            fatalError("unknown variant \(self.variant)")
        }
    }

    func pump(_ seconds: Double) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: min(until, Date().addingTimeInterval(0.05)))
            self.window?.displayIfNeeded()
        }
    }

    /// BENCH_REUSE=1 mirrors the app: one long-lived window whose content is detached on close.
    let reusesWindow = ProcessInfo.processInfo.environment["BENCH_REUSE"] == "1"
    var retainedWindow: NSWindow?

    func open() {
        if self.reusesWindow, let window = self.retainedWindow {
            window.contentViewController = self.makeContentController()
            window.setFrame(NSRect(x: -4000, y: -4000, width: 880, height: 620), display: false)
            window.orderFrontRegardless()
            self.window = window
            return
        }
        let window = OffscreenWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Settings"
        if self.variant == "tabs" {
            window.toolbarStyle = .preference
        }
        window.contentViewController = self.makeContentController()
        window.setFrame(NSRect(x: -4000, y: -4000, width: 880, height: 620), display: false)
        window.orderFrontRegardless()
        self.window = window
        self.retainedWindow = window
    }

    func navigate() {
        let providers = ProviderIcons.names
        let targets: [Pane] = [.app(1), .app(4), .provider(providers[3]), .provider(providers[40]), .app(0)]
        for target in targets {
            if self.variant == "tabs", let tabs = self.window?.contentViewController as? NSTabViewController {
                tabs.selectedTabViewItemIndex = (tabs.selectedTabViewItemIndex + 1) % tabs.tabViewItems.count
            }
            self.selection.pane = target
            self.pump(0.4)
        }
    }

    func close() {
        self.window?.orderOut(nil)
        self.window?.contentViewController = nil
        if !self.reusesWindow {
            self.window?.close()
            self.retainedWindow = nil
        }
        self.window = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.pump(1.0)
        self.samples["launch"] = footprintMiB()
        self.open()
        self.pump(2.0)
        self.samples["open"] = footprintMiB()
        self.navigate()
        self.samples["navigated"] = footprintMiB()
        self.close()
        self.pump(3.0)
        self.samples["closed"] = footprintMiB()
        for _ in 0..<5 {
            self.open()
            self.pump(0.8)
            self.navigate()
            self.close()
            self.pump(0.5)
        }
        self.pump(3.0)
        self.samples["closed_after_6"] = footprintMiB()
        let fields = ["launch", "open", "navigated", "closed", "closed_after_6"].map {
            "\"\($0)\": \(String(format: "%.1f", self.samples[$0] ?? -1))"
        }
        print("{\"variant\": \"\(self.variant)\", \"reuse\": \(self.reusesWindow), \(fields.joined(separator: ", "))}")
        fflush(stdout)
        exit(0)
    }
}

@main
enum Main {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            print("usage: settings-shell-bench <nsv|hstack|appkit-split|tabs> <repo-root>")
            exit(2)
        }
        ProviderIcons.root = arguments[2]
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let bench = Bench(variant: arguments[1])
        app.delegate = bench
        withExtendedLifetime(bench) { app.run() }
    }
}
