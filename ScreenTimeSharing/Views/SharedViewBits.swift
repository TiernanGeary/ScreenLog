import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.976, blue: 0.95), location: 0.0),
                .init(color: Color(red: 1.0, green: 0.99, blue: 0.976), location: 0.18),
                .init(color: Color(red: 0.948, green: 0.978, blue: 1.0), location: 0.46),
                .init(color: Color(red: 0.978, green: 0.99, blue: 1.0), location: 0.64),
                .init(color: .white, location: 0.86),
                .init(color: .white, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct AppSurfaceBackground: View {
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.82

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: Color(red: 0.12, green: 0.18, blue: 0.28).opacity(0.075), radius: 18, x: 0, y: 9)
            .shadow(color: Color(red: 0.96, green: 0.50, blue: 0.20).opacity(0.035), radius: 20, x: 0, y: 4)
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

struct AppScreenScroll<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 128)
        }
        .background(AppBackground())
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
