import Cocoa

/// Custom NSWindow for Pulse — dark chrome, no native tabs, transparent titlebar.
class PulseWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: backingStoreType,
            defer: flag
        )

        // Dark chrome
        self.backgroundColor = NSColor(red: 0x24/255, green: 0x24/255, blue: 0x26/255, alpha: 1)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .visible
        self.title = "Pulse"

        // No native tab bar
        self.tabbingMode = .disallowed

        // Appearance
        self.appearance = NSAppearance(named: .darkAqua)
        self.isMovableByWindowBackground = true

        // Minimum size
        self.minSize = NSSize(width: 600, height: 400)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
