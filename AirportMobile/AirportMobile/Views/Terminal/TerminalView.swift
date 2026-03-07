import SwiftUI

struct TerminalView: View {
    let sessionId: String
    @Environment(AppState.self) private var appState
    @State private var showingPlan = false

    var session: Session? {
        appState.sessions.first { $0.id == sessionId }
    }

    var terminalLines: [String] {
        appState.terminalBuffers[sessionId] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(terminalLines.enumerated()), id: \.offset) { idx, line in
                            Text(stripAnsi(line))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.airportText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(12)
                }
                .background(Color.black)
                .onChange(of: terminalLines.count) { _, count in
                    withAnimation {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }

            // Quick reply bar
            QuickReplyBar(sessionId: sessionId)
        }
        .background(Color.black)
        .navigationTitle(session?.displayTitle ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Status indicator
                    if let session {
                        StatusBadge(session: session)
                    }

                    // Plan button
                    if session?.hasPlans == true {
                        Button {
                            if let session {
                                appState.requestPlan(sessionId: session.id, filename: "")
                            }
                            showingPlan = true
                        } label: {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.airportBlue)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlan) {
            if let session {
                PlanView(session: session)
            }
        }
        .onAppear {
            appState.subscribeTerminal(sessionId: sessionId)
            appState.setActiveSession(id: sessionId)
        }
        .onDisappear {
            appState.unsubscribeTerminal(sessionId: sessionId)
        }
    }

    /// Strip ANSI escape codes for clean display.
    private func stripAnsi(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }
}

struct StatusBadge: View {
    let session: Session

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.sessionStatus(session.status, hookDone: session.hookDone))
                .frame(width: 6, height: 6)
            Text(session.statusText)
                .font(.caption2)
                .foregroundStyle(.airportSubtext)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.airportOverlay)
        .clipShape(Capsule())
    }
}
