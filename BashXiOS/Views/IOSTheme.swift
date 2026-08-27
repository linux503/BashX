import SwiftUI

enum IOSTheme {
    static let accent = Color(red: 0.48, green: 0.66, blue: 0.82)
    static let accentDeep = Color(red: 0.38, green: 0.54, blue: 0.70)
    static let good = Color(red: 0.42, green: 0.72, blue: 0.58)
    static let warn = Color(red: 0.92, green: 0.68, blue: 0.38)
    static let bad = Color(red: 0.88, green: 0.45, blue: 0.48)
    static let ink = Color(red: 0.28, green: 0.36, blue: 0.44)

    static func delay(_ ms: Int?) -> Color {
        guard let ms else { return .secondary }
        if ms < 0 { return bad }
        if ms < 150 { return good }
        if ms < 400 { return warn }
        return bad
    }
}

struct IOSEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(IOSTheme.accent)
                .frame(width: 84, height: 84)
                .background(Circle().fill(IOSTheme.accent.opacity(0.12)))
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.accent)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
