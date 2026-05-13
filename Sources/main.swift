import Cocoa
import CoreGraphics

// MARK: - Virtual Display Manager via ObjC Runtime
// CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplaySettings
// are private CoreGraphics classes. Access them via ObjC runtime instead of
// requiring a C/Dylib bridge.
//
// This tricks macOS into thinking an external monitor is connected, which
// triggers native clamshell mode: lid closes -> built-in display turns off,
// system stays awake for the "external" display.

private func objcClass(_ name: String) -> NSObject.Type? {
    NSClassFromString(name) as? NSObject.Type
}

private func objcCall(_ obj: NSObject, _ sel: String, _ arg: AnyObject) {
    obj.perform(NSSelectorFromString(sel), with: arg)
}

private func objcUInt32(_ obj: NSObject, _ sel: String, _ val: UInt32) {
    typealias Fn = @convention(c) (AnyObject, Selector, UInt32) -> Void
    let m = class_getInstanceMethod(type(of: obj), NSSelectorFromString(sel))!
    unsafeBitCast(method_getImplementation(m), to: Fn.self)(obj, NSSelectorFromString(sel), val)
}

private func objcSize(_ obj: NSObject, _ sel: String, _ val: CGSize) {
    typealias Fn = @convention(c) (AnyObject, Selector, CGSize) -> Void
    let m = class_getInstanceMethod(type(of: obj), NSSelectorFromString(sel))!
    unsafeBitCast(method_getImplementation(m), to: Fn.self)(obj, NSSelectorFromString(sel), val)
}

class VirtualDisplayManager {
    private var display: NSObject?
    private let queue = DispatchQueue(label: "com.lidkeeper.vd", qos: .userInteractive)

    var isActive: Bool { display != nil }

    var displayID: CGDirectDisplayID? {
        guard let d = display else { return nil }
        let sel = NSSelectorFromString("displayID")
        guard d.responds(to: sel) else { return nil }
        typealias GetID = @convention(c) (AnyObject, Selector) -> UInt32
        let m = class_getInstanceMethod(type(of: d), sel)!
        return unsafeBitCast(method_getImplementation(m), to: GetID.self)(d, sel)
    }

    func create() -> Bool {
        guard display == nil else { return true }

        guard let descClass = objcClass("CGVirtualDisplayDescriptor"),
              let displayClass = objcClass("CGVirtualDisplay"),
              let settingsClass = objcClass("CGVirtualDisplaySettings"),
              let modeClass = objcClass("CGVirtualDisplayMode")
        else {
            NSLog("[LidKeeper] CGVirtualDisplay API not available")
            return false
        }

        // Build descriptor
        let desc = descClass.perform(NSSelectorFromString("new"))?
            .takeUnretainedValue() as! NSObject
        objcCall(desc, "setName:", "LidKeeper" as NSString)
        objcUInt32(desc, "setMaxPixelsWide:", 1920)
        objcUInt32(desc, "setMaxPixelsHigh:", 1080)
        objcSize(desc, "setSizeInMillimeters:", CGSize(width: 530, height: 300))
        objcUInt32(desc, "setVendorID:", 0x1337)
        objcUInt32(desc, "setProductID:", 0x0001)
        objcUInt32(desc, "setSerialNum:", 0x0001)
        objcCall(desc, "setDispatchQueue:", queue)

        // Create virtual display
        let initSel = NSSelectorFromString("initWithDescriptor:")
        guard displayClass.instancesRespond(to: initSel) else {
            NSLog("[LidKeeper] initWithDescriptor: unavailable")
            return false
        }

        let allocated = displayClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue() as! NSObject
        guard let vd = allocated.perform(initSel, with: desc)?
            .takeUnretainedValue() as? NSObject
        else {
            NSLog("[LidKeeper] CGVirtualDisplay init failed")
            return false
        }

        // Apply settings
        let mode = createMode(modeClass, width: 1920, height: 1080, refreshRate: 60.0)
        if let mode {
            let settings = settingsClass.perform(NSSelectorFromString("new"))?
                .takeUnretainedValue() as! NSObject
            settings.perform(NSSelectorFromString("setModes:"), with: [mode])
            settings.setValue(2, forKey: "hiDPI")
            vd.perform(NSSelectorFromString("applySettings:"), with: settings)
        }

        display = vd
        NSLog("[LidKeeper] Virtual display created")

        // Mirror to main after a short delay (needs display to settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let id = self?.displayID else { return }
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
            CGConfigureDisplayMirrorOfDisplay(cfg, id, CGMainDisplayID())
            CGCompleteDisplayConfiguration(cfg, .forSession)
        }

        return true
    }

    func destroy() {
        if let id = displayID {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let cfg = config {
                CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
                CGCompleteDisplayConfiguration(cfg, .forSession)
            }
        }
        display = nil
        NSLog("[LidKeeper] Virtual display destroyed")
    }

    private func createMode(_ cls: NSObject.Type, width: Int, height: Int, refreshRate: Double) -> NSObject? {
        let sel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard cls.instancesRespond(to: sel) else { return nil }
        typealias InitFn = @convention(c) (AnyObject, Selector, Int, Int, Double) -> AnyObject?
        let obj = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as! NSObject
        let m = class_getInstanceMethod(cls, sel)!
        return unsafeBitCast(method_getImplementation(m), to: InitFn.self)(obj, sel, width, height, refreshRate) as? NSObject
    }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isEnabled = false {
        didSet { refreshMenuBar() }
    }
    private let vdm = VirtualDisplayManager()
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_: Notification) {
        setupMenuBar()
        enable()
    }

    func applicationWillTerminate(_: Notification) {
        disable()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = drawIcon()

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        toggleMenuItem = NSMenuItem(title: "Turn On", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LidKeeper", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func refreshMenuBar() {
        statusItem.button?.image = drawIcon()
        statusMenuItem.title = isEnabled ? "✅ Virtual Display Active" : "⛔ Disabled"
        toggleMenuItem.title = isEnabled ? "Turn Off" : "Turn On"
    }

    private func drawIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 20))
        img.lockFocus()
        let fill = isEnabled ? NSColor.systemGreen : NSColor.labelColor
        let rect = NSRect(x: 2, y: 3, width: 16, height: 13)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        fill.setFill()
        path.fill()
        if !isEnabled {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: 3, y: 9))
        lid.line(to: NSPoint(x: 17, y: 9))
        lid.lineWidth = 2
        (isEnabled ? NSColor.white : NSColor.labelColor).setStroke()
        lid.stroke()
        let label = (isEnabled ? "Ld" : "L") as NSString
        label.draw(at: NSPoint(x: 7, y: 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: isEnabled ? NSColor.white : NSColor.labelColor
        ])
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    @objc private func toggleEnabled() {
        isEnabled ? disable() : enable()
    }

    @objc private func quitApp() {
        disable()
        NSApplication.shared.terminate(nil)
    }

    private func enable() {
        guard vdm.create() else {
            showAlert("Error", "Failed to create virtual display.\nThis app requires macOS 14+ with CGVirtualDisplay support.")
            return
        }
        isEnabled = true
    }

    private func disable() {
        vdm.destroy()
        isEnabled = false
    }

    private func showAlert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

// MARK: - Entry Point
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
