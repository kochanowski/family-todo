import SwiftUI

struct ShoppingCountBadge: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let count: Int

    var body: some View {
        if themeStore.preset == .retro {
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
            .padding(.vertical, 4)
            .background(Capsule().fill(themeStore.accentTabColor))
    }

    private var retroCoin: some View {
        let label = "\(count)"
        let isWide = count > 9
        let fillColor = themeStore.accentTabColor

        return ZStack {
            if isWide {
                Capsule()
                    .fill(fillColor)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black, lineWidth: 2)
                    }
            } else {
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 2)
                    }
            }

            Text(label)
                .font(.system(size: isWide ? 10 : 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(themeStore.foregroundOnAccent(for: fillColor, colorScheme: colorScheme))
        }
        .frame(width: isWide ? 30 : 22, height: 22)
        .shadow(color: .black.opacity(0.9), radius: 0, x: 2, y: 2)
    }
}
