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
            .background(Capsule().fill(themeStore.accentColor))
    }

    private var retroCoin: some View {
        let label = "\(count)"

        return Text(label)
            .font(themeStore.font(for: .chip))
            .foregroundStyle(.black)
            .padding(.horizontal, label.count > 1 ? 6 : 0)
            .frame(minWidth: 22, minHeight: 22)
            .background {
                Group {
                    if label.count > 1 {
                        Capsule()
                            .fill(Color(hex: "F7D51D"))
                    } else {
                        Circle()
                            .fill(Color(hex: "F7D51D"))
                    }
                }
            }
            .overlay {
                Group {
                    if label.count > 1 {
                        Capsule()
                            .stroke(Color.black, lineWidth: 2)
                    } else {
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    }
                }
            }
            .shadow(color: .black.opacity(0.9), radius: 0, x: 2, y: 2)
    }
}
