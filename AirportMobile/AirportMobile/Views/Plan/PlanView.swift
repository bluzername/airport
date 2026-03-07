import SwiftUI

struct PlanView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let content = session.planContent {
                    // Simple markdown-like rendering
                    Text(LocalizedStringKey(content))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.airportText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.airportBlue)
                        Text("Loading plan...")
                            .foregroundStyle(.airportSubtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                }
            }
            .background(Color.airportBackground)
            .navigationTitle(session.planFilename ?? "Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.airportBlue)
                }
            }
        }
    }
}
