import SwiftUI
import WorderCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Worder")
                .font(.largeTitle.bold())
            Text("Core \(WorderCore.version)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
