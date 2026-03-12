import SwiftUI

/// Bottom status bar showing session stats and keyboard shortcuts.
struct PulseStatusBarView: View {
    @ObservedObject var sessionManager: PulseSessionManager

    var body: some View {
        HStack {
            // Left: stats
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: 0x28C840))
                        .frame(width: 6, height: 6)
                    Text("\(sessionManager.sessions.count) sessions")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: 0x86868B))
                }

                Text("|")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x56565A))

                Text("\(sessionManager.activeSessionCount) active")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x86868B))

                if sessionManager.totalUnreadCount > 0 {
                    Text("|")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: 0x56565A))

                    Text("\(sessionManager.totalUnreadCount) unread")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: 0xE07A5F))
                }
            }

            Spacer()

            // Right: shortcuts
            Text("⌘1-9 switch  ⌘K clear  ⌘W close")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: 0x56565A))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(hex: 0x1E1E20))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }
}
