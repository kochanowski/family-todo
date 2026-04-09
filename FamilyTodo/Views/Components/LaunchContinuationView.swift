import SwiftUI

struct LaunchContinuationView: View {
    @State private var showProgress = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if showProgress {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .task {
            guard !showProgress else { return }
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            showProgress = true
        }
    }
}
