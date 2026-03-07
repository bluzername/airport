import SwiftUI

struct SessionCard: View {
    let session: Session
    var highlight: Bool = false
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            // Header: title + status dot
            HStack {
                Circle()
                    .fill(Color.sessionStatus(session.status, hookDone: session.hookDone))
                    .frame(width: 8, height: 8)

                Text(session.displayTitle)
                    .font(compact ? .subheadline : .headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.airportText)
                    .lineLimit(1)

                Spacer()

                if !session.gitBranch.isEmpty {
                    Text(session.gitBranch)
                        .font(.caption2)
                        .foregroundStyle(.airportSubtext)
                        .lineLimit(1)
                }
            }

            // Status text
            Text(session.statusText)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(session.needsAttention ? .airportRed : .airportSubtext)
                .lineLimit(compact ? 1 : 2)

            // Waiting question preview
            if !session.waitingQuestion.isEmpty && !compact {
                Text(session.waitingQuestion)
                    .font(.caption)
                    .foregroundStyle(.airportText.opacity(0.8))
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.airportOverlay.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(highlight ? Color.airportRed.opacity(0.1) : Color.airportSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            highlight ? Color.airportRed.opacity(0.3) : Color.airportOverlay.opacity(0.5),
                            lineWidth: 1
                        )
                )
        )
        .overlay(alignment: .topTrailing) {
            // Color accent bar
            if !compact {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sessionColor(index: session.colorIndex))
                    .frame(width: 3, height: 20)
                    .padding(.top, 12)
                    .padding(.trailing, 6)
            }
        }
    }
}

// Make Session hashable for NavigationLink
extension Session: Hashable {
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
