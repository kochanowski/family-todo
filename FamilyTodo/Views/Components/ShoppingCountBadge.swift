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
            .background(Capsule().fill(themeStore.resolvedTabTint))
    }

    private var retroCoin: some View {
        let label = "\(count)"
        let isWide = label.count > 1

        return ZStack {
            if isWide {
                Capsule()
                    .fill(Color(hex: "F7D51D"))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black, lineWidth: 2)
                    }
            } else {
                Circle()
                    .fill(Color(hex: "F7D51D"))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 2)
                    }
            }

            Text(label)
                .font(themeStore.font(for: .chip))
                .foregroundStyle(.black)
                .padding(.horizontal, isWide ? 6 : 0)
        }
        .frame(minWidth: 24, minHeight: 24)
        .shadow(color: .black.opacity(0.9), radius: 0, x: 2, y: 2)
    }
}
