import Cocoa

/// Persisted state for a single session (metadata only — the SplitTree is stored separately).
struct PulseSessionState: Codable {
    let id: UUID
    let name: String
    let isCustomName: Bool
    let workingDirectory: String?
    let createdAt: Date
    let focusedSurfaceId: String?
}

/// The complete state of the Pulse app for restoration.
class PulseRestorableState: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    static let version: Int = 1

    let sessions: [PulseSessionState]
    let splitTrees: [UUID: SplitTree<Ghostty.SurfaceView>]
    let activeSessionId: UUID?
    let sidebarCollapsed: Bool

    init(from manager: PulseSessionManager, controller: BaseTerminalController?) {
        // Save current tree for active session
        var trees = manager.splitTreeMap
        if let activeId = manager.activeSessionId,
           let controller = controller {
            trees[activeId] = controller.surfaceTree
        }

        self.sessions = manager.sessions.map { session in
            let focusedId: String? = {
                guard let tree = trees[session.id] else { return nil }
                return tree.first(where: { _ in true })?.id.uuidString
            }()

            return PulseSessionState(
                id: session.id,
                name: session.name,
                isCustomName: session.isCustomName,
                workingDirectory: session.workingDirectory,
                createdAt: session.createdAt,
                focusedSurfaceId: focusedId
            )
        }

        self.splitTrees = trees
        self.activeSessionId = manager.activeSessionId
        self.sidebarCollapsed = manager.sidebarCollapsed
    }

    // MARK: - NSSecureCoding

    func encode(with coder: NSCoder) {
        coder.encode(Self.version, forKey: "version")
        coder.encode(CodableBridge(sessions), forKey: "sessions")
        coder.encode(CodableBridge(splitTrees), forKey: "splitTrees")
        if let activeId = activeSessionId {
            coder.encode(activeId.uuidString, forKey: "activeSessionId")
        }
        coder.encode(sidebarCollapsed, forKey: "sidebarCollapsed")
    }

    required init?(coder: NSCoder) {
        guard coder.decodeInteger(forKey: "version") == Self.version else { return nil }

        guard let sessionsWrapper = coder.decodeObject(
            of: CodableBridge<[PulseSessionState]>.self,
            forKey: "sessions"
        ) else { return nil }

        guard let treesWrapper = coder.decodeObject(
            of: CodableBridge<[UUID: SplitTree<Ghostty.SurfaceView>]>.self,
            forKey: "splitTrees"
        ) else { return nil }

        self.sessions = sessionsWrapper.value
        self.splitTrees = treesWrapper.value

        if let activeIdStr = coder.decodeObject(of: NSString.self, forKey: "activeSessionId") as? String {
            self.activeSessionId = UUID(uuidString: activeIdStr)
        } else {
            self.activeSessionId = nil
        }

        self.sidebarCollapsed = coder.decodeBool(forKey: "sidebarCollapsed")
    }

    // MARK: - Restoration

    /// Restore sessions into a PulseSessionManager.
    /// Creates new SurfaceView instances with the saved working directories.
    func restore(into manager: PulseSessionManager, ghostty: Ghostty.App) {
        guard let app = ghostty.app else { return }

        for sessionState in sessions {
            var config: Ghostty.SurfaceConfiguration? = nil
            if let pwd = sessionState.workingDirectory {
                config = Ghostty.SurfaceConfiguration()
                config?.workingDirectory = pwd
            }

            let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
            let tree = SplitTree<Ghostty.SurfaceView>(view: surfaceView)

            let session = PulseSession(
                id: sessionState.id,
                name: sessionState.name,
                isCustomName: sessionState.isCustomName,
                workingDirectory: sessionState.workingDirectory,
                notificationCount: 0,
                status: .active,
                createdAt: sessionState.createdAt
            )

            manager.sessions.append(session)
            manager.splitTreeMap[session.id] = tree
        }

        manager.sidebarCollapsed = sidebarCollapsed

        if let activeId = activeSessionId,
           manager.sessions.contains(where: { $0.id == activeId }) {
            manager.activeSessionId = activeId
        } else if let first = manager.sessions.first {
            manager.activeSessionId = first.id
        }
    }
}
