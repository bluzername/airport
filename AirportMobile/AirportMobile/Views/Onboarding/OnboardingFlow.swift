import SwiftUI
import AVFoundation

struct OnboardingFlow: View {
    @Environment(AppState.self) private var appState
    @State private var step: OnboardingStep = .welcome
    @State private var manualHost = ""
    @State private var manualPort = "19840"
    @State private var manualCode = ""
    @State private var error: String?
    @State private var isPairing = false

    enum OnboardingStep {
        case welcome
        case scan
        case manual
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .welcome:
                    welcomeView
                case .scan:
                    scanView
                case .manual:
                    manualView
                }
            }
            .background(Color.airportBackground)
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "airplane")
                    .font(.system(size: 64))
                    .foregroundStyle(.airportBlue)

                Text("Airport Mobile")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.airportText)

                Text("Monitor and interact with your Claude Code sessions from your phone.")
                    .font(.body)
                    .foregroundStyle(.airportSubtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                // Auto-discovered servers
                if let browser = appState.bonjourBrowser, !browser.servers.isEmpty {
                    VStack(spacing: 8) {
                        Text("Found on your network:")
                            .font(.subheadline)
                            .foregroundStyle(.airportSubtext)

                        ForEach(browser.servers) { server in
                            Button {
                                // For auto-discovered servers, still need pairing code
                                manualHost = server.host
                                if server.port > 0 {
                                    manualPort = "\(server.port)"
                                }
                                step = .manual
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                    Text(server.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(12)
                                .background(Color.airportOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.airportText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    step = .scan
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.airportBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Button {
                    step = .manual
                } label: {
                    Text("Enter Code Manually")
                        .font(.subheadline)
                        .foregroundStyle(.airportBlue)
                }
            }

            Spacer()
                .frame(height: 40)
        }
    }

    // MARK: - QR Scan

    private var scanView: some View {
        VStack(spacing: 24) {
            Text("Scan the QR code shown in Airport desktop settings")
                .font(.subheadline)
                .foregroundStyle(.airportSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // QR Scanner placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.airportSubtext)
                    Text("Camera preview")
                        .font(.caption)
                        .foregroundStyle(.airportSubtext)
                    Text("(Requires camera permission)")
                        .font(.caption2)
                        .foregroundStyle(.airportSubtext.opacity(0.6))
                }
            }

            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.airportRed)
                    .padding(.horizontal)
            }

            Button("Enter Code Instead") {
                step = .manual
            }
            .foregroundStyle(.airportBlue)

            Spacer()
        }
        .padding(.top)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { step = .welcome }
            }
        }
    }

    // MARK: - Manual Entry

    private var manualView: some View {
        VStack(spacing: 24) {
            Text("Enter the pairing code from Airport desktop")
                .font(.subheadline)
                .foregroundStyle(.airportSubtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Desktop IP Address")
                        .font(.caption)
                        .foregroundStyle(.airportSubtext)
                    TextField("192.168.1.100", text: $manualHost)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.airportSubtext)
                    TextField("19840", text: $manualPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pairing Code")
                        .font(.caption)
                        .foregroundStyle(.airportSubtext)
                    TextField("ABC123", text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)

            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.airportRed)
                    .padding(.horizontal)
            }

            Button {
                Task { await pairManually() }
            } label: {
                if isPairing {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.airportBlue.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            (manualHost.isEmpty || manualCode.isEmpty)
                                ? Color.airportOverlay
                                : Color.airportBlue
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .disabled(manualHost.isEmpty || manualCode.isEmpty || isPairing)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { step = .welcome }
            }
        }
    }

    // MARK: - Pairing

    private func pairManually() async {
        isPairing = true
        error = nil

        do {
            let port = Int(manualPort) ?? 19840
            let result = try await PairingManager.pair(
                host: manualHost,
                port: port,
                token: manualCode
            )

            // Save connection
            let saved = SavedConnection(
                host: result.host,
                port: result.port,
                deviceToken: result.deviceToken,
                serverName: result.serverName,
                pairedAt: Date()
            )
            ConnectionStore.save(saved)
            appState.hasSavedConnection = true
            appState.serverName = result.serverName

            // Connect
            appState.connect(host: result.host, port: result.port, deviceToken: result.deviceToken)

            // Request notification permission
            NotificationManager.requestPermission()
            NotificationManager.setupCategories()

        } catch {
            self.error = error.localizedDescription
        }

        isPairing = false
    }

    private func handleQRScan(_ string: String) async {
        isPairing = true
        error = nil

        do {
            let result = try await PairingManager.pairFromQR(string)

            let saved = SavedConnection(
                host: result.host,
                port: result.port,
                deviceToken: result.deviceToken,
                serverName: result.serverName,
                pairedAt: Date()
            )
            ConnectionStore.save(saved)
            appState.hasSavedConnection = true
            appState.serverName = result.serverName
            appState.connect(host: result.host, port: result.port, deviceToken: result.deviceToken)

            NotificationManager.requestPermission()
            NotificationManager.setupCategories()
        } catch {
            self.error = error.localizedDescription
        }

        isPairing = false
    }
}
