import SwiftUI

/// The collapsed sidebar rail (48px) showing status dots and initials.
struct PulseSidebarRailView: View {
    @ObservedObject var sessionManager: PulseSessionManager
    let onSelectSession: (UUID) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(sessionManager.sessions) { session in
                let isActive = session.id == sessionManager.activeSessionId

                Button(action: { onSelectSession(session.id) }) {
                    ZStack {
                        // Background highlight for active
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isActive ? Color.white.opacity(0.06) : Color.clear)

                        VStack(spacing: 4) {
                            // Status dot
                            Circle()
                                .fill(statusColor(for: session.status))
                                .frame(width: 6, height: 6)

                            // First letter
                            Text(String(session.name.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? Color(hex: 0xF5F5F7) : Color(hex: 0x86868B))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay(
                        // Notification badge
                        Group {
                            if session.notificationCount > 0 {
                                Circle()
                                    .fill(Color(hex: 0xE07A5F))
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Text("\(min(session.notificationCount, 9))")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                        },
                        alignment: .topTrailing
                    )
                }
                .buttonStyle(.plain)
                .help(session.name)
            }

            Spacer()
        }
        .padding(.top, 8)
        .frame(width: 48)
        .background(Color(hex: 0x242426))
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .active: return Color(hex: 0x28C840)
        case .running: return Color(hex: 0xFEBC2E)
        case .idle: return Color(hex: 0x86868B)
        case .disconnected: return Color(hex: 0xFF5F57)
        }
    }
}
