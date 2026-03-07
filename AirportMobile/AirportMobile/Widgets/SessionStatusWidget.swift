import WidgetKit
import SwiftUI

// MARK: - Widget Timeline

struct SessionStatusEntry: TimelineEntry {
    let date: Date
    let totalSessions: Int
    let waitingSessions: Int
    let activeSessions: Int
    let topSession: WidgetSession?
}

struct WidgetSession {
    let title: String
    let status: String
    let color: String
}

struct SessionStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionStatusEntry {
        SessionStatusEntry(
            date: Date(),
            totalSessions: 4,
            waitingSessions: 1,
            activeSessions: 3,
            topSession: WidgetSession(title: "api-refactor", status: "Needs input", color: "#f38ba8")
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionStatusEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionStatusEntry>) -> Void) {
        // Read from shared UserDefaults (app group)
        let entry = readCurrentState()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readCurrentState() -> SessionStatusEntry {
        // In production, read from App Group shared container
        // For now, return placeholder
        return SessionStatusEntry(
            date: Date(),
            totalSessions: 0,
            waitingSessions: 0,
            activeSessions: 0,
            topSession: nil
        )
    }
}

// MARK: - Widget Views

struct SessionStatusWidgetView: View {
    var entry: SessionStatusEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundStyle(Color(hex: "#89b4fa"))
                Text("Airport")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if entry.totalSessions == 0 {
                Text("No sessions")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(entry.totalSessions)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("sessions")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if entry.waitingSessions > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "#f38ba8"))
                                .frame(width: 6, height: 6)
                            Text("\(entry.waitingSessions) need attention")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#f38ba8"))
                        }
                    }
                }
            }
        }
        .padding()
        .containerBackground(Color(hex: "#1e1e2e"), for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: counts
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "airplane")
                        .foregroundStyle(Color(hex: "#89b4fa"))
                    Text("Airport")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.totalSessions) sessions")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(entry.activeSessions) active")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#a6e3a1"))
                    if entry.waitingSessions > 0 {
                        Text("\(entry.waitingSessions) waiting")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#f38ba8"))
                    }
                }
            }

            // Right: top waiting session
            if let top = entry.topSession {
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: top.color))
                            .frame(width: 6, height: 6)
                        Text(top.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(top.status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(Color(hex: "#1e1e2e"), for: .widget)
    }
}

// MARK: - Widget Configuration

struct AirportWidget: Widget {
    let kind = "AirportSessionStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionStatusProvider()) { entry in
            SessionStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Airport Sessions")
        .description("Monitor your Claude Code sessions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
