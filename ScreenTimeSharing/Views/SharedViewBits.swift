import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            stops: colorScheme == .dark ? darkStops : lightStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var lightStops: [Gradient.Stop] {
        [
            .init(color: Color(red: 1.0, green: 0.976, blue: 0.95), location: 0.0),
            .init(color: Color(red: 1.0, green: 0.99, blue: 0.976), location: 0.18),
            .init(color: Color(red: 0.948, green: 0.978, blue: 1.0), location: 0.46),
            .init(color: Color(red: 0.978, green: 0.99, blue: 1.0), location: 0.64),
            .init(color: Color(uiColor: .systemBackground), location: 0.86),
            .init(color: Color(uiColor: .systemBackground), location: 1.0)
        ]
    }

    private var darkStops: [Gradient.Stop] {
        [
            .init(color: Color(red: 0.09, green: 0.12, blue: 0.16), location: 0.0),
            .init(color: Color(red: 0.07, green: 0.09, blue: 0.12), location: 0.34),
            .init(color: Color(uiColor: .systemBackground), location: 1.0)
        ]
    }
}

struct AppSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.82

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surfaceColor.opacity(colorScheme == .dark ? 1 : opacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.8)
            }
            .shadow(color: shadowColor, radius: 18, x: 0, y: 9)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.026), radius: 20, x: 0, y: 4)
    }

    private var surfaceColor: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemGroupedBackground : .systemBackground)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var shadowColor: Color {
        Color(red: 0.12, green: 0.18, blue: 0.28).opacity(colorScheme == .dark ? 0.22 : 0.075)
    }
}

struct AppCardRows<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 2)
    }
}

struct AppCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var opacity: Double = 0.80
    var horizontalPadding: CGFloat = 20
    let content: Content

    init(
        cornerRadius: CGFloat = 22,
        opacity: Double = 0.80,
        horizontalPadding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        AppCardRows {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurfaceBackground(cornerRadius: cornerRadius, opacity: opacity))
    }
}

struct AppCardDivider: View {
    var body: some View {
        Divider()
    }
}

struct AppSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 18)

            content
        }
    }
}

enum AppScreenBackgroundStyle {
    case gradient
    case white
}

struct AppScreenScroll<Content: View>: View {
    var backgroundStyle: AppScreenBackgroundStyle
    let content: Content

    init(
        backgroundStyle: AppScreenBackgroundStyle = .gradient,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundStyle = backgroundStyle
        self.content = content()
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 128)
            }
            .scrollIndicators(.hidden)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 70)

                    Color.black
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: screenBackgroundColor, location: 0.0),
                        .init(color: screenBackgroundColor.opacity(0.96), location: 0.32),
                        .init(color: screenBackgroundColor.opacity(0.72), location: 0.58),
                        .init(color: screenBackgroundColor.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var background: some View {
        switch backgroundStyle {
        case .gradient:
            AppBackground()
        case .white:
            screenBackgroundColor.ignoresSafeArea()
        }
    }

    private var screenBackgroundColor: Color {
        Color(uiColor: .systemBackground)
    }
}

extension View {
    func appSurface(cornerRadius: CGFloat = 16, opacity: Double = 0.82) -> some View {
        background(AppSurfaceBackground(cornerRadius: cornerRadius, opacity: opacity))
    }

    func appCardRow(verticalPadding: CGFloat = 14) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, verticalPadding)
    }

}

enum AppHaptics {
    static func buttonTap() {
        #if canImport(UIKit)
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.68)
        }
        #endif
    }

    static func selectionChanged() {
        #if canImport(UIKit)
        Task { @MainActor in
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}

struct Avatar: View {
    let colorHex: String
    let initials: String

    var body: some View {
        Text(initials)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ProfileAvatar: View {
    let imageData: Data?
    let colorHex: String
    let initials: String
    let size: CGFloat

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarContent: some View {
        #if canImport(UIKit)
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackInitials
        }
        #else
        fallbackInitials
        #endif
    }

    private var fallbackInitials: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex))
    }

    private var shadowColor: Color {
        #if canImport(UIKit)
        if imageData.flatMap(UIImage.init(data:)) != nil {
            return .black.opacity(0.12)
        }
        #endif
        return Color(hex: colorHex).opacity(0.20)
    }
}

struct AppUsageIcon: View {
    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(iconGradient)
            .frame(width: 42, height: 42)
            .overlay {
                Text(initial)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "A"
        }

        return String(first).uppercased()
    }

    private var iconGradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (Color(red: 0.10, green: 0.60, blue: 0.55), Color(red: 0.12, green: 0.42, blue: 0.78)),
            (Color(red: 0.91, green: 0.30, blue: 0.33), Color(red: 0.94, green: 0.55, blue: 0.15)),
            (Color(red: 0.42, green: 0.30, blue: 0.62), Color(red: 0.18, green: 0.46, blue: 0.72)),
            (Color(red: 0.18, green: 0.48, blue: 0.34), Color(red: 0.78, green: 0.56, blue: 0.18))
        ]
        let index = abs(name.hashValue) % palette.count
        let colors = palette[index]

        return LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension UserProfile {
    var initials: String {
        displayName.initials
    }
}

extension String {
    var initials: String {
        let parts = split(separator: " ")
        let characters = parts.prefix(2).compactMap { $0.first }
        if characters.isEmpty, let first {
            return String(first).uppercased()
        }
        return String(characters).uppercased()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
