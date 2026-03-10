import SwiftUI

struct ThemedEmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String?
    let description: String
    let titleFontToken: ThemeFontToken
    let descriptionFontToken: ThemeFontToken
    let actions: Actions

    @EnvironmentObject private var themeStore: ThemeStore

    init(
        title: String,
        systemImage: String? = nil,
        description: String,
        titleFontToken: ThemeFontToken = .screenHeader,
        descriptionFontToken: ThemeFontToken = .listRowTitle,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.titleFontToken = titleFontToken
        self.descriptionFontToken = descriptionFontToken
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 18) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(themeStore.font(for: titleFontToken))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(themeStore.font(for: descriptionFontToken))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !(Actions.self == EmptyView.self) {
                actions
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }
}

extension ThemedEmptyStateView where Actions == EmptyView {
    init(
        title: String,
        systemImage: String? = nil,
        description: String,
        titleFontToken: ThemeFontToken = .screenHeader,
        descriptionFontToken: ThemeFontToken = .listRowTitle
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            description: description,
            titleFontToken: titleFontToken,
            descriptionFontToken: descriptionFontToken
        ) {
            EmptyView()
        }
    }
}
