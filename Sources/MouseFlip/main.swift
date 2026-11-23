import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import ScrollPolicy

extension InputDevice {
    var symbol: String {
        switch self {
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        default: return "cursorarrow"
        }
    }
}

final class MouseMonitor {
    private(set) var devices: [UInt64: InputDevice] = [:]
    private(set) var names: [String] = []
    private(set) var error: String?

    // Discovery needs registry metadata only. Opening IOHIDManager for input
    // can fail without Input Monitoring, independently of Accessibility.
    func refresh() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  IOServiceMatching("IOHIDDevice"), &iterator)
        guard result == KERN_SUCCESS else {
            names = []
            error = "Mouse detection unavailable (\(result))"
            return
        }
        defer { IOObjectRelease(iterator) }
        error = nil
        devices.removeAll(keepingCapacity: true)
        var found = Set<String>()
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any] else { continue }
            let page = (values[kIOHIDPrimaryUsagePageKey] as? NSNumber)?.intValue
            let usage = (values[kIOHIDPrimaryUsageKey] as? NSNumber)?.intValue
            let pairs = values[kIOHIDDeviceUsagePairsKey] as? [[String: Any]] ?? []
            let isMouse = (page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Mouse)
                || pairs.contains {
                    ($0[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue == kHIDPage_GenericDesktop
                    && ($0[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue == kHIDUsage_GD_Mouse
                }
            guard isMouse else { continue }
            let name = values[kIOHIDProductKey] as? String ?? "External mouse"
            let builtIn = (values["Built-In"] as? NSNumber)?.boolValue ?? false
            let kind: InputDevice
            if ScrollPolicy.isExternalMouse(product: name, builtIn: builtIn) {
                found.insert(name)
                kind = .mouse
            } else { kind = .trackpad }
            func register(_ entry: io_registry_entry_t) {
                var id: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS { devices[id] = kind }
            }
            register(device)
            var children: io_iterator_t = 0
            if IORegistryEntryCreateIterator(device, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS {
                while case let child = IOIteratorNext(children), child != 0 {
                    register(child)
                    IOObjectRelease(child)
                }
                IOObjectRelease(children)
            }
        }
        names = found.sorted()
    }
}

final class ScrollFilter {
    var devices: [UInt64: InputDevice] = [:]
    var active: InputDevice = .unknown
    var continuous = false
    private(set) var timeouts = 0
    var changed: (() -> Void)?
    func observe(_ event: CGEvent, scrolling: Bool) {
        // Quartz can expose the sending IORegistry service in field 87.
        let id = UInt64(bitPattern: event.getIntegerValueField(CGEventField(rawValue: 87)!))
        let smooth = scrolling && event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let device: InputDevice
        if let known = devices[id] { device = known }
        else if scrolling {
            device = smooth ? (mouseConnected ? .smooth : .trackpad) : .mouse
        } else { return }
        let isContinuous = scrolling ? smooth : (device == active ? continuous : device == .trackpad)
        if active != device || continuous != isContinuous {
            active = device
            continuous = isContinuous
            changed?()
        }
    }
    var enabled = true
    var mouseConnected = false
    var trackpadNatural = true
    var selectedNatural: Bool {
        ScrollPolicy.direction(for: active, mouse: desiredNatural, trackpad: trackpadNatural,
                               unidentifiedSmoothUsesMouse: includeSmoothScrolling, system: naturalScrolling)
    }
    var desiredNatural = false
    var naturalScrolling = true
    var includeSmoothScrolling = false
    private(set) var wheelEvents = 0
    private(set) var smoothEvents = 0
    private(set) var reversedEvents = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {

        if let tap {
            if CFMachPortIsValid(tap) {
                if !running { CGEvent.tapEnable(tap: tap, enable: true) }
                return
            }
            stop()
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap,
                               eventsOfInterest: [CGEventType.scrollWheel, .mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .rightMouseDragged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) },
                               callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let filter = Unmanaged<ScrollFilter>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if type == .tapDisabledByTimeout { filter.timeouts += 1 }
                if let tap = filter.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                filter.observe(event, scrolling: type == .scrollWheel)
                if type == .scrollWheel { filter.process(event) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func process(_ event: CGEvent) {
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { smoothEvents += 1 }
        else { wheelEvents += 1 }
        guard enabled, naturalScrolling != selectedNatural else { return }
        reversedEvents += 1
        ScrollEventReverser.reverse(event)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var monitor = MouseMonitor()
    private let maintenance = DispatchQueue(label: "MouseFlip.maintenance", qos: .utility)
    private var scanning = false
    private var trusted = false
    private var iconPending = false
    private let filter = ScrollFilter()
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["enabled": true, "smooth": false])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseFlip")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        filter.changed = { [weak self] in
            guard let self, !self.iconPending else { return }
            self.iconPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.iconPending = false
                self.updateIcon()
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if !defaults.bool(forKey: "introduced") {
            defaults.set(true, forKey: "introduced")
            DispatchQueue.main.async { self.showWelcome() }
        }
    }

    private func refresh() {
        guard !scanning else { return }
        scanning = true
        maintenance.async {
            let snapshot = MouseMonitor()
            snapshot.refresh()
            let permission = AXIsProcessTrusted()
            let natural = (CFPreferencesCopyValue("com.apple.swipescrolldirection" as CFString,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.boolValue ?? true
            DispatchQueue.main.async {
                self.monitor = snapshot
                self.trusted = permission
                self.filter.naturalScrolling = natural
                self.scanning = false
                self.applySettings()
            }
        }
    }

    private func applySettings() {
        filter.trackpadNatural = defaults.object(forKey: "trackpadNatural") as? Bool ?? filter.naturalScrolling
        filter.desiredNatural = defaults.bool(forKey: "desiredNatural")
        filter.enabled = defaults.bool(forKey: "enabled")
        filter.includeSmoothScrolling = defaults.bool(forKey: "smooth")
        filter.devices = monitor.devices
        filter.mouseConnected = !monitor.names.isEmpty
        if !filter.mouseConnected && filter.active == .mouse { filter.active = .unknown }
        if trusted { filter.start() } else { filter.stop() }
        updateIcon()
        writeDiagnostics()
    }

    private var previousIcon = ""
    private func updateIcon() {
        let symbol = filter.running ? filter.active.symbol : "cursorarrow"
        if symbol != previousIcon {
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MouseFlip")
                ?? NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "MouseFlip")
            previousIcon = symbol
        }
        statusItem.button?.toolTip = "MouseFlip — " + status
        statusItem.button?.setAccessibilityLabel("MouseFlip — " + status)
    }

    private var status: String {
        if !filter.enabled { return "Paused" }
        if !trusted { return "Accessibility access needed" }
        if let error = monitor.error { return error }
        if !filter.running { return "Scroll filter unavailable — retry access" }
        if filter.active == .unknown { return "Move or scroll to identify the device" }
        let natural = filter.selectedNatural
        return filter.active.rawValue + (natural ? " · Natural scrolling" : " · Traditional scrolling")
    }

    private func writeDiagnostics() {
        // Only state and aggregate counters; no input contents or app activity.
        let report: [String: Any] = [
            "appPath": Bundle.main.bundlePath,
            "status": status,
            "activeDevice": filter.active.rawValue,
            "accessibilityGranted": trusted,
            "eventTapTimeouts": filter.timeouts,
            "tapRunning": filter.running,
            "mice": monitor.names,
            "naturalScrolling": filter.naturalScrolling,
            "desiredNatural": filter.desiredNatural,
            "trackpadNatural": filter.trackpadNatural,
            "enabled": filter.enabled,
            "smoothEnabled": filter.includeSmoothScrolling,
            "wheelEvents": filter.wheelEvents,
            "smoothEvents": filter.smoothEvents,
            "reversedEvents": filter.reversedEvents
        ]
        maintenance.async { Self.saveDiagnostics(report) }
    }

    private static func saveDiagnostics(_ snapshot: [String: Any]) {
        var report = snapshot
        report["updated"] = ISO8601DateFormatter().string(from: Date())
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseFlip", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
        } catch { NSLog("MouseFlip status write failed: %@", error.localizedDescription) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func item(_ title: String, _ action: Selector? = nil, checked: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let checked { item.state = checked ? .on : .off }
        return item
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        menu.addItem(item("MouseFlip"))
        menu.addItem(item(status))
        menu.addItem(item("Scroll events: \(filter.wheelEvents) wheel · \(filter.smoothEvents) smooth · \(filter.reversedEvents) reversed"))
        for name in monitor.names { menu.addItem(item("Connected: \(name)")) }
        menu.addItem(.separator())
        menu.addItem(item("Enable MouseFlip", #selector(toggleEnabled), checked: filter.enabled))
        menu.addItem(item("Natural scrolling for mouse", #selector(toggleNatural), checked: filter.desiredNatural))
        menu.addItem(item("Natural scrolling for trackpad", #selector(toggleTrackpad), checked: filter.trackpadNatural))
        menu.addItem(item("Treat unidentified smooth input as mouse", #selector(toggleSmooth), checked: filter.includeSmoothScrolling))
        menu.addItem(item("Launch at Login", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled))
        if SMAppService.mainApp.status == .requiresApproval {
            menu.addItem(item("Approve Login Item…", #selector(openLoginSettings)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
        menu.addItem(item("About MouseFlip…", #selector(showWelcome)))
        menu.addItem(item("Quit MouseFlip", #selector(quit)))
    }

    @objc private func toggleTrackpad() {
        defaults.set(!filter.trackpadNatural, forKey: "trackpadNatural")
        applySettings()
    }
    @objc private func toggleNatural() {
        defaults.set(!filter.desiredNatural, forKey: "desiredNatural")
        applySettings()
    }
    @objc private func toggleEnabled() { defaults.set(!filter.enabled, forKey: "enabled"); refresh() }
    @objc private func toggleSmooth() {
        defaults.set(!filter.includeSmoothScrolling, forKey: "smooth")
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refresh()
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func grantAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        filter.stop()
        refresh()
    }
    @objc private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "Mouse and trackpad scrolling"
        alert.informativeText = "MouseFlip lives in your menu bar. Choose natural or traditional scrolling independently for your mouse and trackpad in the menu.\n\nGrant Accessibility access to enable the scroll filter. MouseFlip resumes automatically after permission is granted. No scroll events are recorded and no system scrolling preference is changed.\n\nIf your mouse appears as Smooth input, enable Treat unidentified smooth input as mouse."
        alert.addButton(withTitle: AXIsProcessTrusted() ? "Done" : "Open Accessibility Settings")
        if !AXIsProcessTrusted() { alert.addButton(withTitle: "Later") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn && !AXIsProcessTrusted() { grantAccess() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        filter.stop()
    }
}

// Read-only diagnostics exercise exactly the detector used by the app.
if CommandLine.arguments.contains("--check-mice") {
    let monitor = MouseMonitor()
    monitor.refresh()
    print(monitor.error ?? "Detected mice: \(monitor.names.joined(separator: ", "))")
    exit(monitor.error == nil && !monitor.names.isEmpty ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
