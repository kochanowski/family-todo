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
    var uncheckedColor: Color?

    var body: some View {
        Button(action: onToggle) {
            if themeStore.usesRetroChrome {
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
        let resolvedUncheckedColor = uncheckedColor ?? themeStore.checkboxEmptyColor

        switch style {
        case .circle:
            Circle()
                .stroke(resolvedUncheckedColor, lineWidth: 1.5)
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
                .foregroundStyle(isChecked ? checkedColor : resolvedUncheckedColor)
        }
    }

    private var retroCheckbox: some View {
        let accentColor = themeStore.accentTabColor
        let outerBorderColor = themeStore.isRetroLight ? themeStore.borderLightColor : Color.black
        let innerBorderColor = outerBorderColor.opacity(themeStore.isRetroLight ? 0.78 : 0.75)
        let symbolColor = themeStore.foregroundOnAccent(
            for: accentColor,
            colorScheme: themeStore.colorScheme
        )

        Group {
            if isChecked {
                ZStack {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: size + 2, height: size + 2)
                        .overlay {
                            Rectangle()
                                .stroke(outerBorderColor, lineWidth: 3)
                        }
                        .shadow(
                            color: outerBorderColor.opacity(themeStore.isRetroLight ? 0.22 : 1),
                            radius: 0,
                            x: 3,
                            y: 3
                        )

                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.52, height: size * 0.52)
                        .foregroundStyle(symbolColor)
                }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: size + 2, height: size + 2)
                    .overlay {
                        Rectangle()
                            .stroke(accentColor, lineWidth: 2.2)
                    }
                    .overlay {
                        Rectangle()
                            .stroke(innerBorderColor, lineWidth: 1)
                            .padding(0.8)
                    }
            }
        }
    }
}
