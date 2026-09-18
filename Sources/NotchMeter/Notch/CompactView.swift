import SwiftUI

/// Постійний вигляд: по одному крилу обабіч вирізу.
struct CompactView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        let prefs = DisplayPreferences.shared
        HStack(spacing: 0) {
            wing(for: prefs.leftTool, mirrored: false)
                .padding(.trailing, 10)
                .frame(width: Style.compactSideWidth, alignment: .trailing)

            // Під самим вирізом пікселів немає — лишаємо порожнечу.
            Color.clear
                .frame(width: geometry.notchWidth)

            wing(for: prefs.rightTool, mirrored: true)
                .padding(.leading, 10)
                .frame(width: Style.compactSideWidth, alignment: .leading)
        }
        .frame(height: Style.compactHeight)
        // Чорна підкладка продовжує сам виріз: так текст контрастний і на
        // світлих шпалерах, а крила виглядають частиною notch.
        .background(
            BottomRoundedShape(radius: Style.compactCorner)
                .fill(Color.black)
        )
    }

    /// Крила дзеркальні: мітка інструменту стоїть на зовнішньому краї, а
    /// індикатор активності — впритул до вирізу, куди й так дивиться око.
    @ViewBuilder
    private func wing(for id: String, mirrored: Bool) -> some View {
        let short = Style.shortName(for: id)
        let entry = usage.usage(for: id)
        let stale = entry?.isStale ?? true
        let dot = ActivityDot(
            tool: id,
            working: activity.count(for: id, state: .working),
            needsInput: activity.count(for: id, state: .needsInput)
        )

        HStack(spacing: 5) {
            if mirrored { dot }
            if !mirrored { label(short, tool: id) }

            if let window = entry?.window(for: DisplayPreferences.shared.compactWindow) {
                // Мітка обов'язкова: у автоматичному режимі вікно в кожного
                // інструмента своє, та й обране вікно буває недоступним.
                if mirrored {
                    windowTag(window.shortLabel)
                    percent(window.usedPercent, stale: stale)
                    GaugeBar(percent: window.usedPercent, stale: stale)
                } else {
                    GaugeBar(percent: window.usedPercent, stale: stale)
                    percent(window.usedPercent, stale: stale)
                    windowTag(window.shortLabel)
                }
            } else {
                Text("—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if mirrored { label(short, tool: id) }
            if !mirrored { dot }
        }
    }

    private func label(_ text: String, tool: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(nsColor: Style.accent(for: tool)))
    }

    private func windowTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func percent(_ value: Double, stale: Bool) -> some View {
        Text("\(Int(value.rounded()))%")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(stale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .fixedSize()
    }
}
