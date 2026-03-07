import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Workspace picker
                    if appState.workspaces.count > 1 {
                        WorkspacePicker()
                    }

                    // Attention needed
                    let waiting = appState.waitingSessions
                    if !waiting.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Needs Attention")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.airportRed)
                                .padding(.horizontal)

                            ForEach(waiting) { session in
                                NavigationLink(value: session) {
                                    SessionCard(session: session, highlight: true)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Active sessions grid
                    let active = appState.activeSessions
                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sessions")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.airportSubtext)
                                .padding(.horizontal)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ], spacing: 12) {
                                ForEach(active) { session in
                                    NavigationLink(value: session) {
                                        SessionCard(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Backlog
                    let backlog = appState.backlogSessions
                    if !backlog.isEmpty {
                        DisclosureGroup {
                            ForEach(backlog) { session in
                                NavigationLink(value: session) {
                                    SessionCard(session: session, compact: true)
                                }
                                .buttonStyle(.plain)
                            }
                        } label: {
                            Text("Backlog (\(backlog.count))")
                                .font(.subheadline)
                                .foregroundStyle(.airportSubtext)
                        }
                        .padding(.horizontal)
                        .tint(.airportSubtext)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.airportBackground)
            .navigationTitle("Airport")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.airportSubtext)
                    }
                }
            }
            .navigationDestination(for: Session.self) { session in
                TerminalView(sessionId: session.id)
            }
        }
        .tint(.airportBlue)
    }
}

struct WorkspacePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.workspaces) { workspace in
                    Button {
                        appState.switchWorkspace(id: workspace.id)
                    } label: {
                        Text(workspace.name)
                            .font(.subheadline)
                            .fontWeight(workspace.id == appState.activeWorkspaceId ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                workspace.id == appState.activeWorkspaceId
                                    ? Color.airportBlue.opacity(0.2)
                                    : Color.airportOverlay
                            )
                            .foregroundStyle(
                                workspace.id == appState.activeWorkspaceId
                                    ? .airportBlue
                                    : .airportSubtext
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
