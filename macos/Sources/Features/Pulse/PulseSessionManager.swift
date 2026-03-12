import SwiftUI
import Combine

/// Manages all terminal sessions, their split trees, and notification state.
class PulseSessionManager: ObservableObject {
    /// The Ghostty app instance for creating surfaces.
    private let ghostty: Ghostty.App

    /// All sessions in sidebar order.
    @Published var sessions: [PulseSession] = []

    /// The currently active (visible) session ID.
    @Published var activeSessionId: UUID?

    /// Split tree storage for each session. Only the active session's tree
    /// is attached to the PulseWindowController; others are stored here.
    var splitTreeMap: [UUID: SplitTree<Ghostty.SurfaceView>] = [:]

    /// Combine subscriptions for surface title/pwd observation.
    private var surfaceSubscriptions: [UUID: Set<AnyCancellable>] = [:]

    /// Whether the sidebar is in collapsed (rail) mode.
    @Published var sidebarCollapsed: Bool = false

    init(ghostty: Ghostty.App) {
        self.ghostty = ghostty
    }

    // MARK: - Session Lifecycle

    /// Create a new session with an optional base config (for inheriting working directory, etc.).
    /// Returns the new session's ID.
    @discardableResult
    func createSession(baseConfig: Ghostty.SurfaceConfiguration? = nil) -> UUID? {
        guard let app = ghostty.app else { return nil }

        let surfaceView = Ghostty.SurfaceView(app, baseConfig: baseConfig)
        let tree = SplitTree<Ghostty.SurfaceView>(view: surfaceView)

        let session = PulseSession(
            name: PulseSession.autoName(from: surfaceView.pwd)
        )

        sessions.append(session)
        splitTreeMap[session.id] = tree
        subscribeSurface(surfaceView, sessionId: session.id)

        // If this is the first session, make it active
        if sessions.count == 1 {
            activeSessionId = session.id
        }

        return session.id
    }

    /// Close a session by ID. Returns the ID of the session to activate next, or nil if none remain.
    func closeSession(id: UUID) -> UUID? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }

        // Unsubscribe from surface observations
        surfaceSubscriptions.removeValue(forKey: id)

        // Remove split tree (surfaces will deinit and free pty)
        splitTreeMap.removeValue(forKey: id)

        // Remove session
        sessions.remove(at: index)

        // Determine next active session
        if activeSessionId == id {
            if sessions.isEmpty {
                return nil
            }
            // Prefer the session at the same index, or the last one
            let nextIndex = min(index, sessions.count - 1)
            return sessions[nextIndex].id
        }

        return activeSessionId
    }

    /// Close the currently active session.
    func closeActiveSession() -> UUID? {
        guard let activeId = activeSessionId else { return nil }
        return closeSession(id: activeId)
    }

    // MARK: - Session Switching

    /// Switch to a session by ID. Returns the split tree for the new session.
    /// The caller (PulseWindowController) is responsible for saving the current tree
    /// before calling this, and assigning the returned tree to surfaceTree.
    func switchToSession(id: UUID) -> SplitTree<Ghostty.SurfaceView>? {
        guard let _ = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        guard let tree = splitTreeMap[id] else { return nil }

        // Clear notification badge
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].notificationCount = 0
        }

        activeSessionId = id
        return tree
    }

    /// Switch to a session by index (0-based). For Cmd+1 through Cmd+9.
    func switchToSession(index: Int) -> SplitTree<Ghostty.SurfaceView>? {
        guard index >= 0 && index < sessions.count else { return nil }
        return switchToSession(id: sessions[index].id)
    }

    /// Switch to the next session (wraps around).
    func switchToNextSession() -> SplitTree<Ghostty.SurfaceView>? {
        guard let activeId = activeSessionId,
              let currentIndex = sessions.firstIndex(where: { $0.id == activeId }) else { return nil }
        let nextIndex = (currentIndex + 1) % sessions.count
        return switchToSession(id: sessions[nextIndex].id)
    }

    /// Switch to the previous session (wraps around).
    func switchToPreviousSession() -> SplitTree<Ghostty.SurfaceView>? {
        guard let activeId = activeSessionId,
              let currentIndex = sessions.firstIndex(where: { $0.id == activeId }) else { return nil }
        let prevIndex = (currentIndex - 1 + sessions.count) % sessions.count
        return switchToSession(id: sessions[prevIndex].id)
    }

    /// Save the current surface tree for the active session.
    /// Call this before switching sessions.
    func saveCurrentTree(_ tree: SplitTree<Ghostty.SurfaceView>) {
        guard let activeId = activeSessionId else { return }
        splitTreeMap[activeId] = tree
    }

    // MARK: - Session Reordering

    func moveSession(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < sessions.count,
              toIndex >= 0, toIndex < sessions.count else { return }
        let session = sessions.remove(at: fromIndex)
        sessions.insert(session, at: toIndex)
    }

    // MARK: - Session Renaming

    func renameSession(id: UUID, name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].name = name
        sessions[idx].isCustomName = true
    }

    // MARK: - Surface Lookup

    /// Find a surface by UUID across ALL session split trees (including background sessions).
    /// This is critical for Ghostty's action dispatch which needs to find surfaces by UUID.
    func findSurface(id: UUID) -> Ghostty.SurfaceView? {
        for (_, tree) in splitTreeMap {
            for surface in tree where surface.id == id {
                return surface
            }
        }
        return nil
    }

    /// Find which session owns a given surface.
    func findSession(forSurface surfaceId: UUID) -> UUID? {
        for (sessionId, tree) in splitTreeMap {
            for surface in tree where surface.id == surfaceId {
                return sessionId
            }
        }
        return nil
    }

    // MARK: - Notification Tracking

    /// Increment the notification badge for a session (if not currently active).
    func incrementNotification(forSessionOwning surfaceId: UUID) {
        guard let sessionId = findSession(forSurface: surfaceId),
              sessionId != activeSessionId else { return }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].notificationCount += 1
    }

    // MARK: - Combine Observation

    /// Subscribe to a surface's $title and $pwd publishers to auto-update session name.
    private func subscribeSurface(_ surface: Ghostty.SurfaceView, sessionId: UUID) {
        var cancellables = Set<AnyCancellable>()

        surface.$title
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.updateSessionName(sessionId: sessionId, title: title, pwd: nil)
            }
            .store(in: &cancellables)

        surface.$pwd
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pwd in
                self?.updateSessionName(sessionId: sessionId, title: nil, pwd: pwd)
            }
            .store(in: &cancellables)

        surface.$healthy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthy in
                guard let self = self else { return }
                guard let idx = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
                if !healthy {
                    self.sessions[idx].status = .disconnected
                }
            }
            .store(in: &cancellables)

        surfaceSubscriptions[sessionId] = cancellables
    }

    private func updateSessionName(sessionId: UUID, title: String?, pwd: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard !sessions[idx].isCustomName else { return }

        if let pwd = pwd {
            sessions[idx].workingDirectory = pwd
            sessions[idx].name = PulseSession.autoName(from: pwd)
        } else if let title = title, !title.isEmpty {
            sessions[idx].name = title
        }
    }

    // MARK: - Computed Properties

    var activeSessionCount: Int {
        sessions.filter { $0.status == .active || $0.status == .running }.count
    }

    var totalUnreadCount: Int {
        sessions.reduce(0) { $0 + $1.notificationCount }
    }

    var activeSession: PulseSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }
}
