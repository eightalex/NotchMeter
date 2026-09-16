import SwiftUI

/// Постійний вигляд: по одному крилу обабіч вирізу.
struct CompactView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        HStack(spacing: 0) {
            wing(for: "codex", short: "CX", mirrored: false)
                .padding(.trailing, 10)
                .frame(width: Style.compactSideWidth, alignment: .trailing)

            // Під самим вирізом пікселів немає — лишаємо порожнечу.
            Color.clear
                .frame(width: geometry.notchWidth)

            wing(for: "claude", short: "CC", mirrored: true)
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
    private func wing(for id: String, short: String, mirrored: Bool) -> some View {
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

            if let window = entry?.primaryWindow {
                if mirrored {
                    percent(window.usedPercent, stale: stale)
                    GaugeBar(percent: window.usedPercent, stale: stale)
                } else {
                    GaugeBar(percent: window.usedPercent, stale: stale)
                    percent(window.usedPercent, stale: stale)
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

    private func percent(_ value: Double, stale: Bool) -> some View {
        Text("\(Int(value.rounded()))%")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(stale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}
