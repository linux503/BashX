import SwiftUI

/// Realistic produce glyph — uses iOS system emoji (3D-style on modern devices).
struct FruitIconView: View {
    let fruit: FruitKind
    var size: CGFloat = 24

    var body: some View {
        Text(fruit.emoji)
            .font(.system(size: size * 0.92))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.18), radius: 1.2, y: 1)
            .frame(width: size, height: size)
    }
}
