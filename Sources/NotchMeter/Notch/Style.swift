import SwiftUI

enum Style {
    /// Висота фігури у спокої та при наведенні — рівно з рядок меню.
    static func barHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.barHeight
    }

    // Крапки у спокої. Значення підібрані повзунками на справжньому вирізі.

    /// Відступ крапки від краю вирізу.
    static let idleDotInset: CGFloat = 0
    /// Запас між крапкою і зовнішнім краєм фігури: впритул до краю її
    /// підрізає сама фігура.
    static let idleOuterMargin: CGFloat = 8
    /// Зсув крапки вгору (−) чи вниз (+) від центру смуги.
    static let idleDotVerticalOffset: CGFloat = -1

    /// Крило у спокої — рівно під крапку і лічильник поруч («2» чи «2/1»)
    /// та запас до краю фігури.
    static func idleSideWidth(badgeLength: Int) -> CGFloat {
        idleDotInset + PulsingDot.side + badgeWidth(length: badgeLength) + idleOuterMargin
    }

    static func badgeWidth(length: Int) -> CGFloat {
        length > 0 ? CGFloat(length) * 5.5 + 1 : 0
    }

    /// Проміжок між вмістом крила й вирізом.
    static let compactNotchGap: CGFloat = 10

    static let expandedSideWidth: CGFloat = 120

    // Силует: нижні кути та увігнуті «вушки» зверху в кожному стані.
    static let notchCorner: CGFloat = 10
    static let compactCorner: CGFloat = 10
    static let compactEar: CGFloat = 8
    static let expandedCorner: CGFloat = 10
    /// Вушка панелі — такі самі, як при наведенні.
    static let expandedEar: CGFloat = compactEar

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
    /// Наскільки заповнена шкала: використано чи залишок — як обрано.
    let percent: Double
    let stale: Bool
    var width: CGFloat = 30
    var height: CGFloat = 3.5
    /// Скільки ліміту використано — від цього залежить тривожність кольору,
    /// навіть коли шкала показує залишок.
    var usedPercent: Double? = nil
    /// Фірмовий колір агента замість кольору за заповненням.
    var tint: Color? = nil

    var body: some View {
        let fraction = min(max(percent / 100, 0), 1)
        let color = stale
            ? Style.gaugeColor(for: 0, stale: true)
            : tint ?? Style.gaugeColor(for: usedPercent ?? percent, stale: false)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.18))
            Capsule()
                .fill(color)
                .frame(width: max(width * fraction, fraction > 0 ? 2 : 0))
        }
        .frame(width: width, height: height)
    }
}
