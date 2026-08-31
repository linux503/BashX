import SwiftUI

/// Settings row: current icon → tap opens a polished icon gallery.
struct IOSLogoStylePicker: View {
    @Binding var selection: LogoStyle
    var onChange: ((LogoStyle) -> Void)?
    @State private var showGallery = false

    private var resolved: LogoStyle {
        LogoStyle.iosCurated.contains(selection) ? selection : .default
    }

    var body: some View {
        Button {
            showGallery = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [IOSTheme.accentSoft, IOSTheme.tertiaryFill],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    iconImage(resolved)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(resolved.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(resolved.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(L10n.t("ios.icon.change"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IOSTheme.accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if selection != resolved {
                selection = resolved
                onChange?(resolved)
            }
        }
        .sheet(isPresented: $showGallery) {
            IOSIconGallerySheet(selection: $selection, onChange: onChange)
        }
    }

    @ViewBuilder
    private func iconImage(_ style: LogoStyle) -> some View {
        if UIImage(named: style.iosPreviewImageName) != nil {
            Image(style.iosPreviewImageName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                IOSTheme.accentSoft
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundStyle(IOSTheme.accent)
            }
        }
    }
}

private struct IOSIconGallerySheet: View {
    @Binding var selection: LogoStyle
    var onChange: ((LogoStyle) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var styles: [LogoStyle] { IOSIconManager.selectableStyles }
    private var current: LogoStyle {
        LogoStyle.iosCurated.contains(selection) ? selection : .default
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    heroCard
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(styles) { style in
                            cell(style)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(IOSTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(L10n.t("ios.sec.icon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            preview(current)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("ios.icon.current"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(current.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(current.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(IOSTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                )
                .shadow(color: IOSTheme.cardShadow, radius: 12, y: 4)
        )
    }

    private func cell(_ style: LogoStyle) -> some View {
        let selected = current == style
        return Button {
            selection = style
            onChange?(style)
            UISelectionFeedbackGenerator().selectionChanged()
            dismiss()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selected ? IOSTheme.accentSoft : IOSTheme.tertiaryFill.opacity(0.65))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    selected ? IOSTheme.accent.opacity(0.7) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .frame(height: 96)

                    preview(style)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14.3, style: .continuous))
                        .shadow(color: .black.opacity(selected ? 0.18 : 0.10), radius: selected ? 8 : 4, y: 3)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, IOSTheme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }
                }

                Text(style.title)
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? IOSTheme.accentDeep : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func preview(_ style: LogoStyle) -> some View {
        if UIImage(named: style.iosPreviewImageName) != nil {
            Image(style.iosPreviewImageName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                IOSTheme.accentSoft
                Image(systemName: "app.fill")
                    .font(.title)
                    .foregroundStyle(IOSTheme.accent)
            }
        }
    }
}
