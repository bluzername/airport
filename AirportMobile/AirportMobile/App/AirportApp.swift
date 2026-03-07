import SwiftUI

@main
struct AirportApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                DashboardView()
            } else if appState.hasSavedConnection {
                ReconnectingView()
            } else {
                OnboardingFlow()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isConnected)
    }
}

struct ReconnectingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.blue)
            Text("Reconnecting to Airport...")
                .foregroundStyle(.secondary)
            Button("Connect to Different Desktop") {
                appState.clearSavedConnection()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.airportBackground)
    }
}
