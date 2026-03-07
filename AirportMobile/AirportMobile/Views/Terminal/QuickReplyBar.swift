import SwiftUI

struct QuickReplyBar: View {
    let sessionId: String
    @Environment(AppState.self) private var appState
    @State private var replyText = ""
    @FocusState private var isFocused: Bool

    var session: Session? {
        appState.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.airportOverlay)

            // Quick action buttons when session is waiting
            if session?.needsAttention == true {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickButton(label: "Yes", color: .airportGreen) {
                            appState.sendQuickReply(sessionId: sessionId, text: "yes")
                        }
                        QuickButton(label: "No", color: .airportRed) {
                            appState.sendQuickReply(sessionId: sessionId, text: "no")
                        }
                        QuickButton(label: "Continue", color: .airportBlue) {
                            appState.sendQuickReply(sessionId: sessionId, text: "")
                        }
                        QuickButton(label: "Skip", color: .airportYellow) {
                            appState.sendQuickReply(sessionId: sessionId, text: "skip")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            // Text input
            HStack(spacing: 8) {
                TextField("Reply to Claude...", text: $replyText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.airportText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.airportOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($isFocused)
                    .onSubmit {
                        sendReply()
                    }

                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(replyText.isEmpty ? .airportSubtext : .airportBlue)
                }
                .disabled(replyText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.airportSurface)
        }
    }

    private func sendReply() {
        guard !replyText.isEmpty else { return }
        appState.sendQuickReply(sessionId: sessionId, text: replyText)
        replyText = ""
    }
}

struct QuickButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
