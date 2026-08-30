import SwiftUI

/// Unified produce glyph — fruits + bonus vegetables.
struct ProduceIconView: View {
    let fruit: FruitKind
    var vegetable: VegKind? = nil
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let veg = vegetable {
                VegIconView(veg: veg, size: size)
            } else {
                FruitIconView(fruit: fruit, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Cartoon vegetable bonus icons.
struct VegIconView: View {
    let veg: VegKind
    var size: CGFloat = 24

    var body: some View {
        customGlyph
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var customGlyph: some View {
        let s = size
        switch veg {
        case .carrot:
            ZStack {
                CarrotShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.72, blue: 0.32), veg.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: s * 0.42, height: s * 0.82)
                Capsule()
                    .fill(Color(red: 0.32, green: 0.72, blue: 0.32))
                    .frame(width: s * 0.28, height: s * 0.1)
                    .offset(y: -s * 0.36)
            }
        case .tomato:
            roundVeg(s: s, colors: [Color(red: 1, green: 0.42, blue: 0.38), veg.accent]) {
                Capsule().fill(Color(red: 0.32, green: 0.68, blue: 0.28))
                    .frame(width: s * 0.06, height: s * 0.12)
                    .offset(y: -s * 0.34)
            }
        case .broccoli:
            ZStack {
                Capsule()
                    .fill(Color(red: 0.42, green: 0.72, blue: 0.38))
                    .frame(width: s * 0.22, height: s * 0.38)
                    .offset(y: s * 0.18)
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.48, green: 0.82, blue: 0.42), veg.accent],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: s * 0.14
                            )
                        )
                        .frame(width: s * 0.24, height: s * 0.24)
                        .offset(
                            x: cos(Double(i) / 5 * 2 * .pi) * s * 0.16,
                            y: sin(Double(i) / 5 * 2 * .pi) * s * 0.1 - s * 0.08
                        )
                }
            }
        case .corn:
            ZStack {
                Capsule()
                    .fill(Color(red: 0.62, green: 0.48, blue: 0.22))
                    .frame(width: s * 0.18, height: s * 0.42)
                    .offset(y: s * 0.16)
                RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.92, blue: 0.42), veg.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: s * 0.38, height: s * 0.52)
                    .overlay {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: s * 0.04) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Circle()
                                        .fill(Color(red: 0.92, green: 0.78, blue: 0.32))
                                        .frame(width: s * 0.05, height: s * 0.05)
                                }
                            }
                            .offset(y: CGFloat(row - 1) * s * 0.12)
                        }
                    }
            }
        case .eggplant:
            EggplantShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.68, green: 0.42, blue: 0.92), veg.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.48, height: s * 0.78)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(red: 0.32, green: 0.62, blue: 0.28))
                        .frame(width: s * 0.08, height: s * 0.14)
                        .offset(y: -s * 0.04)
                }
        case .bellPepper:
            BellPepperShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.52, blue: 0.38), veg.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.58, height: s * 0.72)
        case .pumpkin:
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 1, green: 0.68, blue: 0.28), veg.accent],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: s * 0.48
                        )
                    )
                Capsule()
                    .fill(Color(red: 0.42, green: 0.62, blue: 0.22))
                    .frame(width: s * 0.06, height: s * 0.14)
                    .offset(y: -s * 0.38)
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(Color(red: 0.72, green: 0.42, blue: 0.12).opacity(0.35))
                        .frame(width: s * 0.04, height: s * 0.22)
                        .offset(y: -s * 0.08)
                        .rotationEffect(.degrees(Double(i - 1) * 18))
                }
            }
        case .cucumber:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.58, green: 0.92, blue: 0.48), veg.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.38, height: s * 0.78)
                .overlay {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: s * 0.04, height: s * 0.12)
                            .offset(y: CGFloat(i - 1) * s * 0.14)
                    }
                }
        case .mushroom:
            ZStack {
                Capsule()
                    .fill(Color(red: 0.92, green: 0.88, blue: 0.78))
                    .frame(width: s * 0.22, height: s * 0.32)
                    .offset(y: s * 0.18)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.92, green: 0.78, blue: 0.62), veg.accent],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: s * 0.38
                        )
                    )
                    .frame(width: s * 0.72, height: s * 0.48)
                    .offset(y: -s * 0.08)
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: s * 0.1, height: s * 0.1)
                    .offset(x: -s * 0.12, y: -s * 0.12)
            }
        case .cabbage:
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.72, green: 0.95, blue: 0.68), veg.accent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: s * 0.38, height: s * 0.22)
                        .offset(y: -s * 0.08)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
                Circle()
                    .fill(Color(red: 0.42, green: 0.72, blue: 0.38).opacity(0.5))
                    .frame(width: s * 0.28, height: s * 0.28)
            }
        }
    }

    private func roundVeg<Detail: View>(s: CGFloat, colors: [Color], @ViewBuilder detail: () -> Detail) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: colors + [colors.last?.opacity(0.85) ?? .clear],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: s * 0.48
                    )
                )
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: s * 0.2, height: s * 0.12)
                .offset(x: -s * 0.1, y: -s * 0.12)
            Ellipse()
                .fill(Color.black.opacity(0.1))
                .frame(width: s * 0.42, height: s * 0.1)
                .offset(y: s * 0.36)
            detail()
        }
    }
}

// MARK: - Shapes

private struct CarrotShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06)
        )
        p.closeSubpath()
        return p
    }
}

private struct EggplantShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12,
                                width: rect.width * 0.56, height: rect.height * 0.82))
        return p
    }
}

private struct BellPepperShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.08),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.08),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.04)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        p.closeSubpath()
        return p
    }
}
