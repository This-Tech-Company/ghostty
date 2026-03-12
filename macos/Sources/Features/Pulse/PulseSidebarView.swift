import SwiftUI

/// The expanded sidebar (240px) showing all sessions and quick actions.
struct PulseSidebarView: View {
    @ObservedObject var sessionManager: PulseSessionManager
    let onCreateSession: () -> Void
    let onSelectSession: (UUID) -> Void
    let onCloseSession: (UUID) -> Void
    let onRenameSession: (UUID, String) -> Void

    @State private var editingSessionId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with top padding for traffic lights
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: 0x86868B))
                    .tracking(0.8)

                Spacer()

                Button(action: onCreateSession) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0x86868B))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)

            // Session list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessionManager.sessions) { session in
                        let isEditingThis = Binding<Bool>(
                            get: { editingSessionId == session.id },
                            set: { newVal in editingSessionId = newVal ? session.id : nil }
                        )

                        PulseSessionRowView(
                            session: session,
                            isActive: session.id == sessionManager.activeSessionId,
                            onRename: { newName in
                                onRenameSession(session.id, newName)
                            },
                            isEditing: isEditingThis
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            editingSessionId = session.id
                        }
                        .onTapGesture(count: 1) {
                            onSelectSession(session.id)
                        }
                        .contextMenu {
                            Button("Rename...") {
                                editingSessionId = session.id
                            }
                            Button("Duplicate") {
                                onCreateSession()
                            }
                            Divider()
                            Button("Close Session") {
                                onCloseSession(session.id)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Quick Actions
            VStack(alignment: .leading, spacing: 0) {
                Text("QUICK ACTIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: 0x56565A))
                    .tracking(0.8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                QuickActionRow(icon: "rectangle.split.2x1", label: "Split Pane", shortcut: "⌘D")
                QuickActionRow(icon: "plus", label: "New Session", shortcut: "⌘T")
                QuickActionRow(icon: "magnifyingglass", label: "Search Output", shortcut: "⌘F")
            }
            .padding(.bottom, 16)
        }
        .frame(width: 240)
        .background(Color(hex: 0x242426))
    }
}

/// A quick action row in the sidebar.
private struct QuickActionRow: View {
    let icon: String
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x56565A))
                .frame(width: 14)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x86868B))

            Spacer()

            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: 0x56565A))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
