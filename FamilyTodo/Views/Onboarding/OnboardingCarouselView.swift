import SwiftUI

// MARK: - Onboarding Slide Data

struct OnboardingSlide: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let subtitle: String
}

private let slides: [OnboardingSlide] = [
    OnboardingSlide(
        id: 0,
        icon: "house.and.flag.fill",
        title: "Your Home, Organized",
        subtitle: "One shared space for everything your household needs to remember."
    ),
    OnboardingSlide(
        id: 1,
        icon: "cart.fill",
        title: "Smart Shopping",
        subtitle: "Shared lists, one-tap restock, and saved bundles for recipes or weekly essentials."
    ),
    OnboardingSlide(
        id: 2,
        icon: "checklist",
        title: "Tasks That Get Done",
        subtitle: "Assign who does what, set due dates, and track progress — no nagging needed."
    ),
    OnboardingSlide(
        id: 3,
        icon: "lightbulb.fill",
        title: "Ideas for Later",
        subtitle: "A parking lot for future plans. When you're ready, promote an idea into a task."
    ),
    OnboardingSlide(
        id: 4,
        icon: "person.2.fill",
        title: "Better Together",
        subtitle: "Invite your household. Changes sync instantly to every phone."
    ),
]

// MARK: - Onboarding Carousel View

struct OnboardingCarouselView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var currentSlide = 0
    private let getStartedSlotHeight = AppChromeMetrics.compactCTAHeight + 8

    var body: some View {
        let isLastSlide = currentSlide == slides.count - 1
        let showSkip = currentSlide > 0 && !isLastSlide

        GeometryReader { proxy in
            let availableHeight = proxy.size.height
            let carouselHeight = min(max(availableHeight * 0.48, 320), 460)

            ZStack(alignment: .topTrailing) {
                // Animated Aurora Background
                AnimatedAuroraBackground(currentSlide: currentSlide)
                    .ignoresSafeArea()

                // Content
                VStack {
                    Spacer()

                    // Paging TabView
                    TabView(selection: $currentSlide) {
                        ForEach(slides) { slide in
                            OnboardingSlideView(slide: slide)
                                .tag(slide.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: carouselHeight)

                    // Page Indicator
                    HStack(spacing: 8) {
                        ForEach(0 ..< slides.count, id: \.self) { index in
                            Circle()
                                .fill(currentSlide == index
                                    ? themeStore.contentPrimaryColor
                                    : themeStore.contentSecondaryColor.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("Slide \(index + 1) of \(slides.count)")
                        }
                    }
                    .padding(.top, 16)

                    Spacer()
                        .frame(height: 40)

                    // Keep a fixed CTA slot so page indicator dots stay vertically stable.
                    ZStack {
                        if isLastSlide {
                            Button {
                                onboardingState.completeOnboarding()
                            } label: {
                                Text("Get Started")
                                    .font(themeStore.font(for: .buttonLabel))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor)
                                    )
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(height: getStartedSlotHeight)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut(duration: 0.25), value: isLastSlide)

                    Spacer()
                        .frame(height: 60)
                }
                .appAdaptiveWidth(
                    maxWidth: AppChromeMetrics.regularFormMaxWidth,
                    alignment: .center
                )

                // Skip button — visible on slides 1–3
                if showSkip {
                    Button {
                        onboardingState.completeOnboarding()
                    } label: {
                        Text("Skip")
                            .font(themeStore.font(for: .listRowSubtitle))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showSkip)
                }
            }
        }
        .onChange(of: currentSlide) { _, _ in
            HapticManager.selection()
        }
    }
}

// MARK: - Single Slide View

private struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        VStack(spacing: 24) {
            // Glassmorphic Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)

                Image(systemName: slide.icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .multilineTextAlignment(.center)

                Text(slide.subtitle)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 40)
    }
}

#Preview {
    OnboardingCarouselView()
        .environmentObject(OnboardingState())
        .environmentObject(ThemeStore())
}
