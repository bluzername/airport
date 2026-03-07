import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Connection") {
                HStack {
                    Label("Status", systemImage: "circle.fill")
                        .foregroundStyle(appState.isConnected ? .airportGreen : .airportRed)
                    Spacer()
                    Text(appState.isConnected ? "Connected" : "Disconnected")
                        .foregroundStyle(.airportSubtext)
                }

                if !appState.serverName.isEmpty {
                    HStack {
                        Label("Desktop", systemImage: "desktopcomputer")
                        Spacer()
                        Text(appState.serverName)
                            .foregroundStyle(.airportSubtext)
                    }
                }
            }

            Section("Actions") {
                Button {
                    appState.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "wifi.slash")
                }

                Button(role: .destructive) {
                    appState.clearSavedConnection()
                } label: {
                    Label("Unpair Device", systemImage: "xmark.circle")
                }
            }

            Section("Notifications") {
                Button {
                    NotificationManager.requestPermission()
                } label: {
                    Label("Enable Notifications", systemImage: "bell")
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.airportSubtext)
                }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color.airportBackground)
    }
}
