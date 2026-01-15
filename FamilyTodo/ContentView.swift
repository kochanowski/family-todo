import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Family To-Do")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Project scaffold ready for CI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("My Tasks")
        }
    }
}

#Preview {
    ContentView()
}
