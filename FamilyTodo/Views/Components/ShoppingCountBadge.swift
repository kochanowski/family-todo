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
            .frame(minWidth: 22, minHeight: 22, alignment: .center)
            .background(Capsule().fill(themeStore.accentTabColor))
            .fixedSize(horizontal: true, vertical: true)
    }

    private var retroCoin: some View {
        let label = "\(count)"
        let fillColor = themeStore.accentTabColor

        return ZStack {
            Circle()
                .fill(fillColor)
                .overlay {
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.7)
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
