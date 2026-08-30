import UIKit

/// Reuse feedback generators — creating one per hit allocates and can spike memory.
enum GameHaptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        soft.prepare()
        light.prepare()
        medium.prepare()
        rigid.prepare()
        heavy.prepare()
        notify.prepare()
    }

    static func softHit(intensity: CGFloat = 0.4) {
        soft.impactOccurred(intensity: intensity)
    }

    static func lightTap(intensity: CGFloat = 0.55) {
        light.impactOccurred(intensity: intensity)
    }

    static func mediumTap(intensity: CGFloat = 0.7) {
        medium.impactOccurred(intensity: intensity)
    }

    static func shatter(heavy isHeavy: Bool) {
        rigid.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            (isHeavy ? heavy : medium).impactOccurred(intensity: isHeavy ? 1.0 : 0.8)
        }
    }

    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
    static func error() { notify.notificationOccurred(.error) }
}
