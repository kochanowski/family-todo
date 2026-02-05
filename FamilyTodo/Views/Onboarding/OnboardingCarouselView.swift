import SwiftUI

// MARK: - Onboarding Slide Data

struct OnboardingSlide: Identifiable {
    let id: Int
    let icon: String
    let headline: String
    let subtext: String
}

private let slides: [OnboardingSlide] = [
    OnboardingSlide(
        id: 0,
        icon: "cloud.fill",
        headline: "Sync your home.",
        subtext: "Keep your shopping lists and daily tasks perfectly in sync with your partner."
    ),
    OnboardingSlide(
        id: 1,
        icon: "basket.fill",
        headline: "Never forget the milk.",
        subtext: "Items move to 'Restock' when checked, ready to be added back for the next trip."
    ),
    OnboardingSlide(
        id: 2,
        icon: "square.3.layers.3d",
        headline: "Dream together.",
        subtext: "A dedicated backlog for home projects, vacations, and gift ideas."
    ),
]

// MARK: - Onboarding Carousel View

struct OnboardingCarouselView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @State private var currentSlide = 0

    var body: some View {
        ZStack {
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
                .frame(height: UIScreen.main.bounds.height * 0.5)

                // Page Indicator
                HStack(spacing: 8) {
                    ForEach(0 ..< slides.count, id: \.self) { index in
                        Circle()
                            .fill(currentSlide == index ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 16)

                Spacer()
                    .frame(height: 40)

                // Get Started Button (only on last slide)
                if currentSlide == slides.count - 1 {
                    Button {
                        onboardingState.completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
                    .frame(height: 60)
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
                Text(slide.headline)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(slide.subtext)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
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
}
