import SwiftUI

enum SessionBadgeSupport {
    static func normalizedLabel(_ text: String) -> String {
        if text.lowercased() == text {
            return text.capitalized
        }
        return text
    }

    static func sessionTone(for status: String) -> Color {
        switch status.lowercased() {
        case "running", "attached", "starting", "awaitinginput":
            return .green
        case "exited":
            return .gray
        case "error":
            return .red
        default:
            return .orange
        }
    }

    static func socketLabel(for state: SessionSocket.ConnectionState, connectedText: String = "connected", disconnectedText: String = "disconnected") -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return connectedText
        case let .disconnected(reason):
            return reason ?? disconnectedText
        }
    }

    static func socketTone(for state: SessionSocket.ConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .idle, .disconnected:
            return .gray
        }
    }

    static func supervisionTone(for session: SessionSummary) -> Color {
        switch session.supervisionStateLabel.lowercased() {
        case "active":
            return .green
        case "stopped":
            return .gray
        default:
            return .orange
        }
    }
}

struct SessionCapsuleBadge: View {
    let text: String
    let tone: Color
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 6
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text)
            .dynamicBadgeFont(weight: weight)
            .foregroundStyle(tone)
            .frame(width: width, height: height)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.opacity(0.18))
            .clipShape(Capsule())
    }
}

private struct DynamicBadgeFontModifier: ViewModifier {
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(size: 100, weight: weight, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.01)
            .allowsTightening(true)
    }
}

extension View {
    func dynamicBadgeFont(weight: Font.Weight = .semibold) -> some View {
        modifier(DynamicBadgeFontModifier(weight: weight))
    }
}
