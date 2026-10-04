import SwiftUI

/// Постійний вигляд: по одному крилу обабіч вирізу.
struct CompactView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        let prefs = DisplayPreferences.shared
        let sideWidth = Style.compactSideWidth(badgeLength: IdleView.badgeLength(in: activity))
        HStack(spacing: 0) {
            wing(for: prefs.leftTool, mirrored: false)
                .padding(.trailing, Style.compactNotchGap)
                .frame(width: sideWidth, alignment: .trailing)

            // Під самим вирізом пікселів немає — лишаємо порожнечу.
            Color.clear
                .frame(width: geometry.notchWidth)

            wing(for: prefs.rightTool, mirrored: true)
                .padding(.leading, Style.compactNotchGap)
                .frame(width: sideWidth, alignment: .leading)
        }
        .frame(height: Style.barHeight(for: geometry))
    }

    /// Складові крила — в порядку для лівого крила, від зовнішнього краю до
    /// вирізу. Праве крило дзеркальне: мітка агента завжди на зовнішньому
    /// краї, а індикатор активності — впритул до вирізу.
    private enum Element: Hashable {
        case label, gauge, percent, windowTag, resetTime, activity, missing
    }

    private func elements(hasWindow: Bool) -> [Element] {
        let content = ContentPreferences.shared.values
        var result: [Element] = []
        if content.hoverLabel != .hidden { result.append(.label) }
        if hasWindow {
            if content.hoverShowsGauge { result.append(.gauge) }
            if content.hoverShowsPercent { result.append(.percent) }
            if content.hoverShowsWindowTag { result.append(.windowTag) }
            if content.hoverShowsResetTime { result.append(.resetTime) }
        } else {
            result.append(.missing)
        }
        if content.hoverShowsActivity { result.append(.activity) }
        return result
    }

    @ViewBuilder
    private func wing(for tool: Tool, mirrored: Bool) -> some View {
        let window = usage.usage(for: tool)?.window(for: DisplayPreferences.shared.compactWindow)
        let order = elements(hasWindow: window != nil)

        HStack(spacing: 5) {
            ForEach(mirrored ? order.reversed() : order, id: \.self) { element in
                view(for: element, tool: tool, window: window, mirrored: mirrored)
            }
        }
    }

    @ViewBuilder
    private func view(for element: Element, tool: Tool, window: LimitWindow?, mirrored: Bool) -> some View {
        let content = ContentPreferences.shared.values
        let stale = usage.usage(for: tool)?.isStale ?? true

        switch element {
        case .label:
            switch content.hoverLabel {
            case .logo:
                AgentLogo(tool: tool, size: 11)
            case .logoAndShort:
                HStack(spacing: 3) {
                    if mirrored { labelText(tool.shortName, tool: tool) }
                    AgentLogo(tool: tool, size: 11)
                    if !mirrored { labelText(tool.shortName, tool: tool) }
                }
            case .full:
                labelText(tool.displayName, tool: tool)
            case .short, .hidden:
                labelText(tool.shortName, tool: tool)
            }
        case .gauge:
            if let window {
                GaugeBar(
                    percent: content.hoverPercentMode.value(fromUsed: window.currentPercent),
                    stale: stale,
                    usedPercent: window.currentPercent,
                    tint: content.hoverGaugeColoring == .accent ? Color(nsColor: tool.accent) : nil
                )
            }
        case .percent:
            if let window {
                percent(content.hoverPercentMode.value(fromUsed: window.currentPercent), stale: stale)
            }
        case .windowTag:
            if let window { smallText(window.shortLabel) }
        case .resetTime:
            if let reset = window?.resetShortDescription { smallText(reset) }
        case .activity:
            ActivityDot(
                tool: tool,
                working: activity.count(for: tool, state: .working),
                needsInput: activity.count(for: tool, state: .needsInput),
                showsBadge: content.hoverShowsBadge
            )
        case .missing:
            Text("—")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func labelText(_ text: String, tool: Tool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(nsColor: tool.accent))
            .fixedSize()
    }

    private func smallText(_ text: String) -> some View {
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
