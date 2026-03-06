import SwiftUI

struct MemberBadgeView: View {
    enum DisplayStyle {
        case regular
        case compact
    }

    @EnvironmentObject private var themeStore: ThemeStore

    let name: String
    let colorHex: String
    var displayStyle: DisplayStyle = .regular

    private var badgeColor: Color {
        Color(hex: colorHex)
    }

    private var foregroundColor: Color {
        MemberColorToken.foregroundForBadge(hex: colorHex)
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var displayedName: String {
        switch displayStyle {
        case .regular:
            return name
        case .compact:
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName
        }
    }

    private var avatarSize: CGFloat {
        switch displayStyle {
        case .regular:
            20
        case .compact:
            18
        }
    }

    var body: some View {
        HStack(spacing: displayStyle == .compact ? 6 : 4) {
            Text(initial)
                .font(.system(size: displayStyle == .compact ? 9 : 10, weight: .bold))
                .foregroundStyle(foregroundColor)
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(badgeColor))

            Text(displayedName)
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentPrimaryColor)
                .lineLimit(1)
        }
        .padding(.leading, displayStyle == .compact ? 2 : 2)
        .padding(.trailing, displayStyle == .compact ? 7 : 8)
        .padding(.vertical, displayStyle == .compact ? 2 : 3)
        .background(Capsule().fill(badgeColor.opacity(0.16)))
    }
}

struct RecurringIndicatorView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Image(systemName: "repeat")
            .font(themeStore.font(for: .chip))
            .foregroundStyle(themeStore.accentTabColor)
            .accessibilityLabel("Recurring task")
    }
}
