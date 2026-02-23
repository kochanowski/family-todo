import SwiftUI

struct ShoppingCountBadge: View {
    @EnvironmentObject private var themeStore: ThemeStore

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
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(themeStore.selectedTabColor))
    }

    private var retroCoin: some View {
        let label = "\(count)"
        let isWide = count > 9
        let fillColor = themeStore.selectedTabColor

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
                .font(.custom("PressStart2P-Regular", size: isWide ? 7 : 8))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .offset(y: isWide ? 0 : -0.5)
        }
        .frame(width: isWide ? 30 : 22, height: 22)
        .shadow(color: .black.opacity(0.9), radius: 0, x: 2, y: 2)
    }
}
