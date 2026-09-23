import SwiftUI

enum Style {
    static let compactHeight: CGFloat = 32
    /// Вистачає на мітку, шкалу, «100%», мітку вікна й крапку з лічильником.
    static let compactSideWidth: CGFloat = 120
    /// Відступ крапки активності від краю вирізу. Калібровка показала, що
    /// виріз не зачіпає крапку вже з 12pt; далі — питання вигляду.
    static let idleDotInset: CGFloat = 24

    /// Крило у спокої — рівно під крапку і лічильник поруч («2» чи «2/1»):
    /// за ними фігура одразу закінчується, без зайвого чорного поля.
    static func idleSideWidth(badgeLength: Int) -> CGFloat {
        let dot = PulsingDot.side
        let badge = badgeLength > 0 ? CGFloat(badgeLength) * 5.5 + 1 : 0
        return idleDotInset + dot + badge
    }
    static let expandedSideWidth: CGFloat = 100

    // Силует: нижні кути та увігнуті «вушки» зверху в кожному стані.
    static let notchCorner: CGFloat = 10
    static let compactCorner: CGFloat = 10
    static let compactEar: CGFloat = 6
    static let expandedCorner: CGFloat = 22
    static let expandedEar: CGFloat = 10

    /// Місце під тінь розгорнутої панелі.
    static let shadowMargin: CGFloat = 28
    /// Пружина на мить виносить фігуру за кінцевий розмір — вікно на час
    /// анімації має бути трохи більшим, інакше її край обріжеться.
    static let springSlack: CGFloat = 18

    /// Що ближче до вичерпання ліміту, то тривожніший колір.
    static func gaugeColor(for percent: Double, stale: Bool) -> Color {
        if stale { return Color.secondary }
        switch percent {
        case ..<60: return Color(nsColor: .systemGreen)
        case ..<85: return Color(nsColor: .systemYellow)
        default: return Color(nsColor: .systemRed)
        }
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
