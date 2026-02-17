import SwiftUI

enum ThemedCheckboxStyle {
    case circle
    case square
}

struct ThemedCheckbox: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let isChecked: Bool
    let onToggle: () -> Void
    var size: CGFloat = 22
    var style: ThemedCheckboxStyle = .circle
    var checkedColor: Color = .green
    var uncheckedColor: Color = .secondary.opacity(0.35)

    var body: some View {
        Button(action: onToggle) {
            if themeStore.preset == .retro {
                retroCheckbox
            } else {
                defaultCheckbox
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var defaultCheckbox: some View {
        switch style {
        case .circle:
            Circle()
                .stroke(uncheckedColor, lineWidth: 1.5)
                .frame(width: size, height: size)
                .overlay {
                    if isChecked {
                        Circle()
                            .fill(checkedColor)
                            .frame(width: size * 0.65, height: size * 0.65)
                    }
                }
        case .square:
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(.system(size: size))
                .foregroundStyle(isChecked ? checkedColor : uncheckedColor)
        }
    }

    private var retroCheckbox: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: "F7D51D"))
                .frame(width: size + 2, height: size + 2)
                .overlay {
                    Rectangle()
                        .stroke(Color.black, lineWidth: 3)
                }
                .shadow(color: .black, radius: 0, x: 3, y: 3)

            if isChecked {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.52, height: size * 0.52)
                    .foregroundStyle(.black)
            }
        }
    }
}
