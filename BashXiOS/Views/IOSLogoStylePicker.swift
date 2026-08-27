import SwiftUI

struct IOSLogoStylePicker: View {
    @Binding var selection: LogoStyle
    var onChange: ((LogoStyle) -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var styles: [LogoStyle] { IOSIconManager.selectableStyles }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(styles) { style in
                Button {
                    selection = style
                    onChange?(style)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selection == style ? IOSTheme.accentSoft : IOSTheme.tertiaryFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            selection == style ? IOSTheme.accent.opacity(0.65) : IOSTheme.cardStroke,
                                            lineWidth: selection == style ? 1.5 : 0.5
                                        )
                                )
                            preview(for: style)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .frame(height: 58)
                        .shadow(color: selection == style ? IOSTheme.accent.opacity(0.15) : .clear, radius: 8, y: 4)

                        Text(style.title)
                            .font(.caption2.weight(selection == style ? .bold : .medium))
                            .foregroundStyle(selection == style ? IOSTheme.accentDeep : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func preview(for style: LogoStyle) -> some View {
        if UIImage(named: style.iosPreviewImageName) != nil {
            Image(style.iosPreviewImageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            // Never leave an empty cell if asset is missing.
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundStyle(IOSTheme.accent)
        }
    }
}
