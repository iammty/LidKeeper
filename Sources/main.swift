import Cocoa
import IOKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isEnabled = false
    private var lidClosed = false
    private var displaySleepTimer: Timer?
    private var lidPollTimer: Timer?
    private var caffeinateProcess: Process?

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
            button.image = makeIcon(color: .gray)
        }

        let menu = NSMenu()

        let statusLabel = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLabel.identifier = NSUserInterfaceItemIdentifier("status")
        menu.addItem(statusLabel)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Turn Off", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.identifier = NSUserInterfaceItemIdentifier("toggle")
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LidKeeper", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Icon Drawing

    private func makeIcon(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 12, height: 12)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled ? disable() : enable()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Enable / Disable

    private func enable() {
        isEnabled = true
        updateUI()
        shell("pmset", "-a", "displaysleep", "0")
        startCaffeinate()
        startLidPolling()
    }

    private func disable() {
        isEnabled = false
        lidClosed = false
        updateUI()
        stopDisplaySleepLoop()
        stopLidPolling()
        stopCaffeinate()
        shell("pmset", "-a", "displaysleep", "30")
    }

    private func updateUI() {
        statusItem.button?.image = makeIcon(color: isEnabled ? .systemGreen : .gray)
        guard let menu = statusItem.menu else { return }

        let statusText: String
        if !isEnabled {
            statusText = "Disabled"
        } else if lidClosed {
            statusText = "Active — lid closed"
        } else {
            statusText = "Active — lid open"
        }

        if let item = menu.item(withIdentifier: NSUserInterfaceItemIdentifier("status")) {
            item.title = statusText
        }
        if let item = menu.item(withIdentifier: NSUserInterfaceItemIdentifier("toggle")) {
            item.title = isEnabled ? "Turn Off" : "Turn On"
        }
    }

    // MARK: - Caffeinate

    private func startCaffeinate() {
        let p = Process()
        p.launchPath = "/usr/bin/caffeinate"
        p.arguments = ["-i", "-m", "-s"]
        try? p.run()
        caffeinateProcess = p
    }

    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    // MARK: - Lid Polling

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
        guard lidClosed != wasClosed else { return }

        if lidClosed {
            startDisplaySleepLoop()
        } else {
            stopDisplaySleepLoop()
        }
        updateUI()
    }

    private func readClamshellState() -> Bool {
        let entry = IORegistryGetRootEntry(0)
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        guard let value = IORegistryEntryCreateCFProperty(
            entry, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else {
            return false
        }
        return value
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
        task.launchPath = "/usr/bin/env"
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
