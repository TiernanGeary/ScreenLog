import SwiftUI

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
