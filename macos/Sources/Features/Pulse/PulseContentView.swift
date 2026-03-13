import SwiftUI

/// Root SwiftUI view for Pulse — sidebar + terminal content + status bar.
struct PulseContentView: View {
    @ObservedObject var sessionManager: PulseSessionManager
    @ObservedObject var ghostty: Ghostty.App

    /// The view model provided by PulseWindowController (which is a TerminalViewModel).
    @ObservedObject var viewModel: BaseTerminalController

    let onCreateSession: () -> Void
    let onSelectSession: (UUID) -> Void
    let onCloseSession: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Sidebar
                if sessionManager.sidebarCollapsed {
                    PulseSidebarRailView(
                        sessionManager: sessionManager,
                        onSelectSession: onSelectSession
                    )
                    .transition(.move(edge: .leading))
                } else {
                    PulseSidebarView(
                        sessionManager: sessionManager,
                        onCreateSession: onCreateSession,
                        onSelectSession: onSelectSession,
                        onCloseSession: onCloseSession,
                        onRenameSession: { id, name in
                            sessionManager.renameSession(id: id, name: name)
                        }
                    )
                    .transition(.move(edge: .leading))
                }

                // Divider between sidebar and content
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)

                // Terminal content area
                TerminalView(
                    ghostty: ghostty,
                    viewModel: viewModel,
                    delegate: viewModel,
                    onCreateSession: onCreateSession,
                    onToggleSidebar: {
                        sessionManager.sidebarCollapsed.toggle()
                    },
                    onCloseSession: {
                        if let activeId = sessionManager.activeSessionId {
                            onCloseSession(activeId)
                        }
                    }
                )
            }

            // Status bar
            PulseStatusBarView(sessionManager: sessionManager)
        }
        .background(Color(hex: 0x1A1A1C))
    }
}
