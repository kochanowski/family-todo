import SwiftUI

struct MemberBadgeView: View {
    @EnvironmentObject private var themeStore: ThemeStore

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
        HStack(spacing: 4) {
            Text(initial)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foregroundColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(badgeColor))

            Text(name)
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentPrimaryColor)
        }
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(badgeColor.opacity(0.16)))
    }
}
