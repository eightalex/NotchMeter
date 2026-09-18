import SwiftUI

/// Стан спокою: біля вирізу лишаються тільки крапки активності, та й ті —
/// лише коли якийсь агент працює або чекає на відповідь.
///
/// Крапки стоять на помітній відстані від вирізу: впритул до нього їх
/// підрізає край екрана.
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
        .background(
            BottomRoundedShape(radius: Style.compactCorner)
                .fill(Color.black)
        )
    }

    private var sideWidth: CGFloat {
        Style.idleSideWidth(hasBadge: IdleView.hasBadge(in: activity))
    }

    /// Обидва крила однакові, тож ширину визначає найширше з них.
    static func hasBadge(in activity: ActivityStore) -> Bool {
        DisplayPreferences.tools.contains { tool in
            ActivityDot.badge(
                working: activity.count(for: tool, state: .working),
                needsInput: activity.count(for: tool, state: .needsInput)
            ) != nil
        }
    }

    private func dot(for id: String) -> some View {
        ActivityDot(
            tool: id,
            working: activity.count(for: id, state: .working),
            needsInput: activity.count(for: id, state: .needsInput)
        )
    }
}
