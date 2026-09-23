import SwiftUI

/// Стан спокою: біля вирізу лишаються тільки крапки активності, та й ті —
/// лише коли якийсь агент працює або чекає на відповідь.
///
/// Крапки стоять трохи осторонь вирізу, щоб не зливатися з його краєм.
struct IdleView: View {
    let geometry: NotchGeometry
    var activity: ActivityStore

    var body: some View {
        HStack(spacing: 0) {
            dot(for: DisplayPreferences.shared.leftTool)
                .padding(.trailing, Style.idleDotInset)
                .frame(width: sideWidth, alignment: .trailing)

            Color.clear.frame(width: geometry.notchWidth)

            dot(for: DisplayPreferences.shared.rightTool)
                .padding(.leading, Style.idleDotInset)
                .frame(width: sideWidth, alignment: .leading)
        }
        .frame(height: Style.compactHeight)
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
