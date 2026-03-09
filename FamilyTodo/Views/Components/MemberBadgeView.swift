import SwiftUI

struct MemberBadgeView: View {
    let name: String
    let colorHex: String

    private var badgeColor: Color {
        Color(hex: colorHex)
    }

    private var foregroundColor: Color {
        MemberColorToken.foregroundForBadge(hex: colorHex)
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foregroundColor)
            .frame(width: 22, height: 22)
            .background(Circle().fill(badgeColor))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}
