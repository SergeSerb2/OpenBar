import AppKit
import Darwin
import Foundation

/// Self-driving memory scenario for before/after footprint comparisons. Inert unless
/// `OPENBAR_MEMORY_PROBE_DIR` is set at launch. When armed it waits for startup work to settle,
/// then opens the merged menu and cycles every switcher tab, opens Settings on Usage & Spend,
/// closes it, forces a refresh, and reopens the menu. Each step appends the process footprint
/// to `events.csv` so an external sampler can align its timeline with the scenario.
@MainActor
enum MemoryScenarioProbe {
    private static var session: Session?

    static func startIfRequested(controller: StatusItemController) {
        let environment = ProcessInfo.processInfo.environment
        guard let dir = environment["OPENBAR_MEMORY_PROBE_DIR"], !dir.isEmpty else { return }
        let delay = environment["OPENBAR_MEMORY_PROBE_DELAY"].flatMap(TimeInterval.init) ?? 90
        let session = Session(controller: controller, directory: URL(fileURLWithPath: dir, isDirectory: true))
        self.session = session
        session.record("armed")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            session.run()
        }
    }

    nonisolated static func physicalFootprintMB() -> Double {
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

    @MainActor
    final class Session {
        private let controller: StatusItemController
        private let directory: URL
        private let start = Date()

        init(controller: StatusItemController, directory: URL) {
            self.controller = controller
            self.directory = directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func record(_ event: String) {
            let elapsed = Date().timeIntervalSince(self.start)
            let line = String(format: "%.1f,%@,%.1f\n", elapsed, event, MemoryScenarioProbe.physicalFootprintMB())
            let url = self.directory.appendingPathComponent("events.csv")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? ("t,event,footprint_mb\n" + line).write(to: url, atomically: true, encoding: .utf8)
            }
        }

        func run() {
            self.record("idle")
            self.cycleMenu(label: "menu1") { [self] in
                self.after(5) {
                    self.record("menu1-closed+5s")
                    self.controller.settingsOpenHandler?(.usageSpend)
                    self.after(15) {
                        self.record("settings-spend-open+15s")
                        self.settingsWindow()?.performClose(nil)
                        self.after(10) {
                            self.record("settings-closed+10s")
                            self.controller.refreshNow()
                            self.after(45) {
                                self.record("refresh+45s")
                                self.cycleMenu(label: "menu2") { [self] in
                                    self.after(30) {
                                        self.record("menu2-closed+30s")
                                        self.after(120) {
                                            self.record("settled+150s")
                                            self.record("done")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        private func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { body() }
            }
        }

        private func settingsWindow() -> NSWindow? {
            NSApp.windows.first { $0.identifier?.rawValue == SettingsWindowIdentity.identifier }
        }

        /// Opens the merged menu, selects every switcher segment once, then closes the menu.
        /// `openMenuFromShortcut` blocks in NSMenu tracking, so a common-modes timer drives it.
        private func cycleMenu(label: String, completion: @escaping @MainActor () -> Void) {
            let cycler = MenuCycler(session: self, label: label)
            let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated { cycler.tick() }
            }
            cycler.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            self.controller.openMenuFromShortcut()
            self.waitForClose(cycler, label: label, completion: completion)
        }

        /// The merged menu can open asynchronously, so poll until the cycler finished.
        private func waitForClose(
            _ cycler: MenuCycler,
            label: String,
            completion: @escaping @MainActor () -> Void)
        {
            guard cycler.finished else {
                self.after(0.5) { self.waitForClose(cycler, label: label, completion: completion) }
                return
            }
            self.record("\(label)-closed")
            completion()
        }

        var openMenu: NSMenu? {
            self.controller.openMenus.values.first
        }
    }

    @MainActor
    final class MenuCycler {
        private unowned let session: Session
        private let label: String
        var timer: Timer?
        private(set) var finished = false
        private var ticks = 0
        private var segmentIndex = 0
        private var segmentCount: Int?

        init(session: Session, label: String) {
            self.session = session
            self.label = label
        }

        func tick() {
            self.ticks += 1
            let menu = self.session.openMenu
            guard let segmentCount else {
                guard let menu else {
                    if self.ticks > 200 {
                        self.session.record("\(self.label)-not-found")
                        self.stop()
                    }
                    return
                }
                let switcher = menu.items.first?.view as? ProviderSwitcherView
                self.segmentCount = switcher?.segmentCountForProbe ?? 0
                self.session.record("\(self.label)-open")
                return
            }
            // Advance one segment per second, then close.
            guard self.ticks % 20 == 0 else { return }
            if self.segmentIndex < segmentCount,
               let switcher = menu?.items.first?.view as? ProviderSwitcherView
            {
                _ = switcher.handleKeyboardSelection(at: self.segmentIndex)
                self.segmentIndex += 1
                return
            }
            self.session.record("\(self.label)-before-close")
            self.stop()
            menu?.cancelTracking()
        }

        private func stop() {
            self.timer?.invalidate()
            self.timer = nil
            self.finished = true
        }
    }
}
