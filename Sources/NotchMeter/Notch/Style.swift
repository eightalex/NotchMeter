import SwiftUI

enum Style {
    static let compactHeight: CGFloat = 32
    static let compactSideWidth: CGFloat = 104
    /// Крила у спокої — під крапку активності з запасом, щоб її не підрізав
    /// край вирізу.
    /// Відступ від краю вирізу. Великий навмисно: система повідомляє межі
    /// вирізу з запасом, і все, що ближче, він підрізає.
    static let idleDotInset: CGFloat = 40

    /// Крапка сама по собі вузька, а з лічильником («2/1») — помітно ширша.
    static func idleSideWidth(hasBadge: Bool) -> CGFloat {
        idleDotInset + (hasBadge ? 40 : 18)
    }
    static let expandedSideWidth: CGFloat = 100
    static let expandedCorner: CGFloat = 14
    static let compactCorner: CGFloat = 10

    /// Що ближче до вичерпання ліміту, то тривожніший колір.
    static func gaugeColor(for percent: Double, stale: Bool) -> Color {
        if stale { return Color.secondary }
        switch percent {
        case ..<60: return Color(nsColor: .systemGreen)
        case ..<85: return Color(nsColor: .systemYellow)
        default: return Color(nsColor: .systemRed)
        }
    }

    /// Фірмові акценти інструментів: Claude — помаранчевий, Codex — синій.
    static let claudeAccent = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    static let codexAccent = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)

    static func accent(for tool: String) -> NSColor {
        tool == "claude" ? claudeAccent : codexAccent
    }

    static let warningColor = Color(nsColor: .systemYellow)

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Тонка шкала заповнення ліміту.
struct GaugeBar: View {
    let percent: Double
    let stale: Bool
    var width: CGFloat = 30
    var height: CGFloat = 3.5

    var body: some View {
        let fraction = min(max(percent / 100, 0), 1)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.18))
            Capsule()
                .fill(Style.gaugeColor(for: percent, stale: stale))
                .frame(width: max(width * fraction, fraction > 0 ? 2 : 0))
        }
        .frame(width: width, height: height)
    }
}
