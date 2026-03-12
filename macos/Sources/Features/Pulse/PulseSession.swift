import Foundation

/// Status of a terminal session's process.
enum SessionStatus: Codable, Equatable {
    case active       // green — shell ready for input
    case running      // yellow — process executing
    case idle         // gray — no recent activity
    case disconnected // red — pty closed/errored
}

/// A single terminal session in the Pulse sidebar.
struct PulseSession: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isCustomName: Bool
    var workingDirectory: String?
    var notificationCount: Int
    var status: SessionStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "New Session",
        isCustomName: Bool = false,
        workingDirectory: String? = nil,
        notificationCount: Int = 0,
        status: SessionStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isCustomName = isCustomName
        self.workingDirectory = workingDirectory
        self.notificationCount = notificationCount
        self.status = status
        self.createdAt = createdAt
    }

    /// Auto-generate a display name from working directory.
    /// Extracts the last path component (e.g., "~/Apps/TTC/pulse" → "pulse").
    static func autoName(from pwd: String?) -> String {
        guard let pwd = pwd, !pwd.isEmpty else { return "shell" }
        let expanded = pwd.hasPrefix("~")
            ? pwd
            : (pwd as NSString).lastPathComponent
        return (expanded as NSString).lastPathComponent
    }
}
