import SwiftUI

extension Color {
    // Catppuccin Mocha palette — matches Airport desktop
    static let airportBackground = Color(hex: "#1e1e2e")
    static let airportSurface = Color(hex: "#181825")
    static let airportOverlay = Color(hex: "#313244")
    static let airportSubtext = Color(hex: "#a6adc8")
    static let airportText = Color(hex: "#cdd6f4")
    static let airportBlue = Color(hex: "#89b4fa")
    static let airportGreen = Color(hex: "#a6e3a1")
    static let airportYellow = Color(hex: "#f9e2af")
    static let airportRed = Color(hex: "#f38ba8")
    static let airportMauve = Color(hex: "#cba6f7")
    static let airportTeal = Color(hex: "#94e2d5")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Session status color
    static func sessionStatus(_ status: SessionStatus, hookDone: Bool) -> Color {
        if hookDone { return .airportRed }
        switch status {
        case .active: return .airportGreen
        case .idle: return .airportSubtext
        case .standby: return .airportYellow
        case .waitingForInput: return .airportRed
        }
    }

    /// Palette colors for session tiles (matches desktop colorIndex)
    static let sessionPalette: [Color] = [
        .airportBlue,
        .airportGreen,
        .airportMauve,
        .airportYellow,
        .airportTeal,
        .airportRed,
        Color(hex: "#fab387"), // peach
        Color(hex: "#74c7ec"), // sapphire
    ]

    static func sessionColor(index: Int) -> Color {
        sessionPalette[index % sessionPalette.count]
    }
}
