import Cocoa
import SwiftUI
import Combine

/// The single window controller for Pulse. Subclasses BaseTerminalController
/// to inherit split tree management, focus tracking, undo, clipboard, and fullscreen.
class PulseWindowController: BaseTerminalController {

    /// The session manager.
    let sessionManager: PulseSessionManager

    /// The Pulse content hosting view.
    private var contentHostingView: NSHostingView<PulseContentView>?

    /// Local event monitor for session-switching shortcuts.
    /// performKeyEquivalent on NSWindowController is NOT in the responder chain,
    /// so we use a local event monitor to intercept Cmd+1-9 and Cmd+Shift+[/].
    private var keyMonitor: Any?

    // MARK: - Static APIs (replacements for TerminalController statics)

    /// The singleton PulseWindowController (set during init).
    static weak var shared: PulseWindowController?

    /// Compatibility shim for code that references TerminalController.all
    static var all: [PulseWindowController] {
        if let shared = shared { return [shared] } else { return [] }
    }

    /// Compatibility shim for TerminalController.preferredParent
    static var preferredParent: PulseWindowController? { shared }

    // MARK: - Initialization

    /// Initialize with a Ghostty app and session manager.
    /// Creates the first session's surface immediately to avoid BaseTerminalController
    /// creating an orphan surface (its init creates a default when tree is nil).
    init(_ ghostty: Ghostty.App, sessionManager: PulseSessionManager) {
        self.sessionManager = sessionManager

        // Create the first session's surface immediately so we can pass it as the initial tree.
        guard let app = ghostty.app else { preconditionFailure("app must be loaded") }
        let initialSurface = Ghostty.SurfaceView(app, baseConfig: nil)
        let initialTree = SplitTree<Ghostty.SurfaceView>(view: initialSurface)

        super.init(ghostty, surfaceTree: initialTree)

        // Register the initial surface as a session
        let session = PulseSession(name: PulseSession.autoName(from: initialSurface.pwd))
        sessionManager.sessions.append(session)
        sessionManager.splitTreeMap[session.id] = initialTree
        sessionManager.activeSessionId = session.id

        // Create the window programmatically (no NIB — BaseTerminalController inits with window: nil)
        let window = PulseWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.delegate = self

        setupContentView()
        setupKeyMonitor()
        setupPulseNotificationObservers()

        PulseWindowController.shared = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupContentView() {
        guard let window = self.window else { return }

        let contentView = PulseContentView(
            sessionManager: sessionManager,
            ghostty: ghostty,
            viewModel: self,
            onCreateSession: { [weak self] in
                self?.createNewSession()
            },
            onSelectSession: { [weak self] id in
                self?.switchToSession(id: id)
            },
            onCloseSession: { [weak self] id in
                self?.closeSession(id: id)
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hostingView
        self.contentHostingView = hostingView
    }

    // MARK: - Session Operations

    func createNewSession(baseConfig: Ghostty.SurfaceConfiguration? = nil) {
        // Save current tree before creating
        saveCurrentTree()

        guard let sessionId = sessionManager.createSession(baseConfig: baseConfig) else { return }

        // Switch to the new session
        switchToSession(id: sessionId)
    }

    func switchToSession(id: UUID) {
        guard id != sessionManager.activeSessionId else { return }

        // Save current tree
        saveCurrentTree()

        // Get new tree and swap
        guard let newTree = sessionManager.switchToSession(id: id) else { return }
        self.surfaceTree = newTree
        syncFocusToSurfaceTree()
    }

    func closeSession(id: UUID) {
        let nextId = sessionManager.closeSession(id: id)

        if let nextId = nextId {
            // Switch to the next session
            if let tree = sessionManager.splitTreeMap[nextId] {
                sessionManager.activeSessionId = nextId
                self.surfaceTree = tree
                syncFocusToSurfaceTree()
            }
        } else {
            // No sessions left — quit app
            NSApp.terminate(nil)
        }
    }

    private func saveCurrentTree() {
        sessionManager.saveCurrentTree(self.surfaceTree)
    }

    // MARK: - Sidebar Toggle

    func toggleSidebar() {
        sessionManager.sidebarCollapsed.toggle()
    }

    // MARK: - Keyboard Shortcuts (Local Event Monitor)

    /// NSWindowController is NOT in the responder chain for performKeyEquivalent.
    /// Use a local event monitor to intercept session-switching shortcuts before
    /// they reach libghostty (whose gotoTab/moveTab have tab group guards that
    /// fail in single-window mode).
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard event.window === self.window else { return event }
            guard event.modifierFlags.contains(.command) else { return event }

            let key = event.charactersIgnoringModifiers ?? ""

            // Cmd+B: toggle sidebar
            if key == "b" && !event.modifierFlags.contains(.shift) {
                self.toggleSidebar()
                return nil
            }

            // Cmd+1 through Cmd+9: switch to session by index
            if let digit = Int(key), digit >= 1 && digit <= 9 {
                self.saveCurrentTree()
                if let tree = self.sessionManager.switchToSession(index: digit - 1) {
                    self.surfaceTree = tree
                    self.syncFocusToSurfaceTree()
                }
                return nil // consume event
            }

            // Cmd+Shift+] and Cmd+Shift+[: next/previous session
            if event.modifierFlags.contains(.shift) {
                if key == "]" {
                    self.saveCurrentTree()
                    if let tree = self.sessionManager.switchToNextSession() {
                        self.surfaceTree = tree
                        self.syncFocusToSurfaceTree()
                    }
                    return nil
                } else if key == "[" {
                    self.saveCurrentTree()
                    if let tree = self.sessionManager.switchToPreviousSession() {
                        self.surfaceTree = tree
                        self.syncFocusToSurfaceTree()
                    }
                    return nil
                }
            }

            return event // pass through
        }
    }

    // MARK: - Pulse Notification Observers

    /// Register observers for notifications that TerminalController previously handled.
    /// These are NOT in AppDelegate — they were registered in TerminalController.init().
    private func setupPulseNotificationObservers() {
        let center = NotificationCenter.default

        // Close tab → close active session
        center.addObserver(
            self,
            selector: #selector(pulseCloseTab(_:)),
            name: .ghosttyCloseTab,
            object: nil)

        // Close window → close active session (quit if last)
        center.addObserver(
            self,
            selector: #selector(pulseCloseWindow(_:)),
            name: .ghosttyCloseWindow,
            object: nil)

        // Move tab → reorder session
        center.addObserver(
            self,
            selector: #selector(pulseMoveTab(_:)),
            name: .ghosttyMoveTab,
            object: nil)

        // Toggle fullscreen (was in TerminalController, needed for fullscreen support)
        center.addObserver(
            self,
            selector: #selector(pulseToggleFullscreen(_:)),
            name: Ghostty.Notification.ghosttyToggleFullscreen,
            object: nil)

        // Desktop notification for badge tracking
        center.addObserver(
            self,
            selector: #selector(pulseDesktopNotification(_:)),
            name: .pulseDesktopNotification,
            object: nil)
    }

    @objc private func pulseCloseTab(_ notification: Notification) {
        guard let activeId = sessionManager.activeSessionId else { return }
        closeSession(id: activeId)
    }

    @objc private func pulseCloseWindow(_ notification: Notification) {
        guard let activeId = sessionManager.activeSessionId else { return }
        closeSession(id: activeId)
    }

    @objc private func pulseMoveTab(_ notification: Notification) {
        // Future: implement session reordering via Ghostty action
    }

    @objc private func pulseToggleFullscreen(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
        // Only handle if the surface belongs to our tree
        guard surfaceTree.contains(where: { $0.id == surfaceView.id }) else { return }

        // Extract the fullscreen mode from userInfo (matches TerminalController behavior)
        let fullscreenMode: FullscreenMode
        if let any = notification.userInfo?[Ghostty.Notification.FullscreenModeKey],
           let mode = any as? FullscreenMode {
            fullscreenMode = mode
        } else {
            Ghostty.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }
        toggleFullscreen(mode: fullscreenMode)
    }

    @objc private func pulseDesktopNotification(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
        sessionManager.incrementNotification(forSessionOwning: surfaceView.id)
    }

    // MARK: - Window Delegate

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        // Save state before closing
        saveCurrentTree()
        // Quit app when the single window closes
        NSApp.terminate(nil)
    }
}

// MARK: - Pulse Notification Names

extension Notification.Name {
    static let pulseDesktopNotification = Notification.Name("com.pulse.desktopNotification")
}
