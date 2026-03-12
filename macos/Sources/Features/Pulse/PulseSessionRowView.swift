import SwiftUI

/// A single session row in the Pulse sidebar.
struct PulseSessionRowView: View {
    let session: PulseSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Name and working directory
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? Color(hex: 0xF5F5F7) : Color(hex: 0xB0B0B3))
                    .lineLimit(1)

                if let pwd = session.workingDirectory {
                    Text(pwd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: isActive ? 0x86868B : 0x56565A))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Notification badge
            if session.notificationCount > 0 {
                Text("\(session.notificationCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color(hex: 0xE07A5F))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isActive ? Color.white.opacity(0.06) : Color.clear)
        .overlay(
            Rectangle()
                .fill(isActive ? Color(hex: 0xE07A5F) : Color.clear)
                .frame(width: 2),
            alignment: .leading
        )
    }

    private var statusColor: Color {
        switch session.status {
        case .active: return Color(hex: 0x28C840)
        case .running: return Color(hex: 0xFEBC2E)
        case .idle: return Color(hex: 0x86868B)
        case .disconnected: return Color(hex: 0xFF5F57)
        }
    }
}

// MARK: - Color Extension (defined once here, used across all Pulse views)

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
