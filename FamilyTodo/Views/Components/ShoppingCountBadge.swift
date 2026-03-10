import SwiftUI

struct ShoppingCountBadge: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let count: Int

    var body: some View {
        if themeStore.usesRetroChrome {
            retroCoin
        } else {
            standardBadge
        }
    }

    private var standardBadge: some View {
        Text("\(count)")
            .font(themeStore.font(for: .chip))
            .foregroundStyle(themeStore.foregroundOnAccent(for: themeStore.accentTabColor, colorScheme: colorScheme))
            .padding(.horizontal, 8)
            .frame(minWidth: 22, minHeight: 22, alignment: .center)
            .background(Capsule().fill(themeStore.accentTabColor))
            .fixedSize(horizontal: true, vertical: true)
    }

    private var retroCoin: some View {
        let label = "\(count)"
        let fillColor = themeStore.accentTabColor
        let borderColor = themeStore.isRetroLight ? themeStore.borderLightColor : Color.black

        return ZStack {
            Circle()
                .fill(fillColor)
                .overlay {
                    Circle()
                        .strokeBorder(borderColor, lineWidth: 1.7)
                }

            Text(label)
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(themeStore.foregroundOnAccent(for: fillColor, colorScheme: colorScheme))
                .padding(.horizontal, 2)
        }
        .frame(width: 22, height: 22)
    }
}

struct TasksWIPBadge: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let count: Int
    let limit: Int

    private var isOverLimit: Bool {
        count > limit
    }

    private var fillColor: Color {
        isOverLimit ? .red : themeStore.accentTabColor
    }

    var body: some View {
        Text("\(count)/\(limit)")
            .font(themeStore.font(for: .chip))
            .fontWeight(isOverLimit ? .bold : .semibold)
            .monospacedDigit()
            .foregroundStyle(themeStore.foregroundOnAccent(for: fillColor, colorScheme: colorScheme))
            .padding(.horizontal, 10)
            .frame(minHeight: 24, alignment: .center)
            .background(Capsule().fill(fillColor))
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel("WIP \(count) of \(limit)")
    }
}
