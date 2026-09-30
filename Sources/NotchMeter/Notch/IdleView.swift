import SwiftUI

/// Стан спокою: біля вирізу лишаються тільки крапки активності, та й ті —
/// лише коли якийсь агент працює або чекає на відповідь.
///
/// Крапки стоять трохи осторонь вирізу, щоб не зливатися з його краєм.
struct IdleView: View {
    let geometry: NotchGeometry
    var activity: ActivityStore

    var body: some View {
        // Крило — це прозора підкладка фіксованої ширини, а крапка лежить
        // поверх неї. Раніше крапка сама задавала крило, і коли агент мовчав,
        // крило схлопувалось до нуля: весь вміст з'їжджав на пів крила й
        // переставав збігатися з вирізом.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: sideWidth)
                .overlay(alignment: .trailing) {
                    dot(for: DisplayPreferences.shared.leftTool)
                        .padding(.trailing, Style.idleDotInset)
                        .modifier(VerticalNudge(offset: Style.idleDotVerticalOffset))
                }

            Color.clear.frame(width: geometry.notchWidth)

            Color.clear
                .frame(width: sideWidth)
                .overlay(alignment: .leading) {
                    dot(for: DisplayPreferences.shared.rightTool)
                        .padding(.leading, Style.idleDotInset)
                        .modifier(VerticalNudge(offset: Style.idleDotVerticalOffset))
                }
        }
        .frame(height: Style.barHeight(for: geometry))
    }

    private var sideWidth: CGFloat {
        Style.idleSideWidth(badgeLength: IdleView.badgeLength(in: activity))
    }

    /// Обидва крила однакові, тож ширину визначає найдовший лічильник.
    static func badgeLength(in activity: ActivityStore) -> Int {
        DisplayPreferences.tools.map { tool in
            ActivityDot.badge(
                working: activity.count(for: tool, state: .working),
                needsInput: activity.count(for: tool, state: .needsInput)
            )?.count ?? 0
        }.max() ?? 0
    }

    private func dot(for id: Tool) -> some View {
        ActivityDot(
            tool: id,
            working: activity.count(for: id, state: .working),
            needsInput: activity.count(for: id, state: .needsInput)
        )
    }
}

/// Зсув по вертикалі відступами, а не `.offset`: крапка — шар AppKit, і
/// `.offset` SwiftUI вона ігнорує, а відступи враховує.
private struct VerticalNudge: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.top, max(0, offset * 2))
            .padding(.bottom, max(0, -offset * 2))
    }
}
