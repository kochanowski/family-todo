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

struct MemberNameChipView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let name: String
    let colorHex: String

    private var chipColor: Color {
        Color(hex: colorHex)
    }

    private var foregroundColor: Color {
        MemberColorToken.foregroundForBadge(hex: colorHex)
    }

    var body: some View {
        Text(name)
            .font(themeStore.font(for: .bodySmall))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(chipColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}
