import Cocoa
import IOKit

// MARK: - C bridge declarations
// These are implemented in pm_helper.c using IOKit PM C API
// (IOKit.pm symbols not exposed in Swift module)

@_silgen_name("pm_prevent_system_sleep")
func pm_preventSystemSleep(_ reason: UnsafePointer<CChar>) -> UInt32

@_silgen_name("pm_no_idle_sleep")
func pm_noIdleSleep(_ reason: UnsafePointer<CChar>) -> UInt32

@_silgen_name("pm_release_assertion")
func pm_releaseAssertion(_ assertionID: UInt32) -> Bool

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var isEnabled = false
    private var lidClosed = false
    private var displaySleepTimer: Timer?
    private var lidPollTimer: Timer?
    private var caffeinateProcess: Process?

    // IOPMAssertion handles (from C bridge)
    private var preventSleepAssertion: UInt32 = 0
    private var noIdleSleepAssertion: UInt32 = 0

    // Menu item references (avoid NSMenu.item(withIdentifier:) which needs macOS 14+)
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        enable()
    }

    func applicationWillTerminate(_ notification: Notification) {
        disable()
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = drawIcon()
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "Turn Off", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LidKeeper", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Icon Drawing

    private func drawIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let color: NSColor = isEnabled ? .systemGreen : .systemGray

        // Body
        let rect = NSRect(x: 2, y: 3, width: 14, height: 11)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        color.setFill()
        path.fill()

        // Lid line
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: 3, y: 9))
        lid.line(to: NSPoint(x: 15, y: 9))
        lid.lineWidth = 2.5
        NSColor.white.setStroke()
        lid.stroke()

        // "zZ" when active
        if isEnabled {
            let zz = "zZ" as NSString
            zz.draw(at: NSPoint(x: 7, y: 5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 5, weight: .bold),
                .foregroundColor: NSColor.white
            ])
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        if isEnabled { disable() } else { enable() }
    }

    @objc private func quitApp() {
        disable()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Enable / Disable

    private func enable() {
        isEnabled = true
        updateUI()

        // 1. Create IOPMAssertions (stronger than caffeinate)
        preventSleepAssertion = "LidKeeper:preventSystemSleep".withCString { ptr in
            pm_preventSystemSleep(ptr)
        }
        noIdleSleepAssertion = "LidKeeper:noIdleSleep".withCString { ptr in
            pm_noIdleSleep(ptr)
        }

        if preventSleepAssertion == 0 && noIdleSleepAssertion == 0 {
            // Fallback to caffeinate if assertions failed
            startCaffeinate()
        }

        // 2. Prevent display timeout (we control it manually)
        shell("pmset", "-a", "displaysleep", "0")

        // 3. Read initial lid state
        lidClosed = readClamshellState()
        if lidClosed {
            startDisplaySleepLoop()
        }

        // 4. Start polling
        startLidPolling()
    }

    private func disable() {
        isEnabled = false
        lidClosed = false
        updateUI()

        stopDisplaySleepLoop()
        stopLidPolling()
        stopCaffeinate()
        releaseAssertions()
        shell("pmset", "-a", "displaysleep", "30")
    }

    private func releaseAssertions() {
        if preventSleepAssertion != 0 {
            _ = pm_releaseAssertion(preventSleepAssertion)
            preventSleepAssertion = 0
        }
        if noIdleSleepAssertion != 0 {
            _ = pm_releaseAssertion(noIdleSleepAssertion)
            noIdleSleepAssertion = 0
        }
    }

    private func updateUI() {
        statusItem.button?.image = drawIcon()

        let statusText: String
        if !isEnabled {
            statusText = "⛔ Disabled"
        } else if lidClosed {
            statusText = "✅ Lid Closed — Display Off"
        } else {
            statusText = "✅ Lid Open — Running"
        }
        statusMenuItem.title = statusText
        toggleMenuItem.title = isEnabled ? "Turn Off" : "Turn On"
    }

    // MARK: - Caffeinate (fallback)

    private func startCaffeinate() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-i", "-m", "-s", "-u"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        caffeinateProcess = p
    }

    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    // MARK: - Lid Polling via IOKit

    private func startLidPolling() {
        lidPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateLidState()
        }
    }

    private func stopLidPolling() {
        lidPollTimer?.invalidate()
        lidPollTimer = nil
    }

    private func updateLidState() {
        let wasClosed = lidClosed
        lidClosed = readClamshellState()
        guard lidClosed != wasClosed else {
            // Even if state hasn't changed, keep display off while lid is closed
            if lidClosed {
                shell("pmset", "displaysleepnow")
            }
            return
        }

        if lidClosed {
            startDisplaySleepLoop()
        } else {
            stopDisplaySleepLoop()
        }
        updateUI()
    }

    /// Read AppleClamshellState from the IOKit registry.
    private func readClamshellState() -> Bool {
        let matching = IOServiceMatching("AppleClamshellState")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let prop = IORegistryEntryCreateCFProperty(
            service,
            "ClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let p = prop else { return false }
        return (p.takeRetainedValue() as? Bool) ?? false
    }

    // MARK: - Display Sleep Loop

    private func startDisplaySleepLoop() {
        stopDisplaySleepLoop()
        shell("pmset", "displaysleepnow")
        displaySleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.shell("pmset", "displaysleepnow")
        }
    }

    private func stopDisplaySleepLoop() {
        displaySleepTimer?.invalidate()
        displaySleepTimer = nil
    }

    // MARK: - Shell Helper

    @discardableResult
    private func shell(_ args: String...) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

// MARK: - Entry Point
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
