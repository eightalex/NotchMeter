import SwiftUI

/// Постійний вигляд: по одному крилу обабіч вирізу.
///
/// Крила однакові за шириною — фігура лишається симетричною відносно
/// вирізу. Ширина береться з виміряного вмісту ширшого крила, тож відступ від
/// зовнішнього краю (`hoverEdgePadding`) і проміжок біля вирізу
/// (`Style.compactNotchGap`) завжди точні. У вужчому крилі перший елемент
/// (зазвичай логотип) лишається біля краю, решта — біля вирізу, а зайве
/// місце йде між ними.
struct CompactView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        let prefs = DisplayPreferences.shared
        let sideWidth = Self.sideWidth(usage: usage, activity: activity)
        let edge = Self.edgePadding
        HStack(spacing: 0) {
            CompactWing(tool: prefs.leftTool, mirrored: false, stretch: true, usage: usage, activity: activity)
                .padding(.leading, edge)
                .padding(.trailing, Style.compactNotchGap)
                .frame(width: sideWidth)

            // Під самим вирізом пікселів немає — лишаємо порожнечу.
            Color.clear
                .frame(width: geometry.notchWidth)

            CompactWing(tool: prefs.rightTool, mirrored: true, stretch: true, usage: usage, activity: activity)
                .padding(.leading, Style.compactNotchGap)
                .padding(.trailing, edge)
                .frame(width: sideWidth)
        }
        .frame(height: Style.barHeight(for: geometry))
    }

    @MainActor static var edgePadding: CGFloat {
        CGFloat(ContentPreferences.shared.values.hoverEdgePadding)
    }

    // MARK: - Ширина крил

    @MainActor private static var cachedSignature: String?
    @MainActor private static var cachedContentWidth: CGFloat = 0

    /// Ширина одного крила: вміст ширшого з двох плюс відступи. Міряємо
    /// справжню верстку, а не вгадуємо: відсотки, мітки й логотипи мають
    /// різну ширину. Результат кешуємо за всім, що впливає на вміст, —
    /// перевірка йде кожні чверть секунди, а вимір потрібен, лише коли
    /// щось змінилось.
    @MainActor
    static func sideWidth(usage: UsageStore, activity: ActivityStore) -> CGFloat {
        let signature = Self.signature(usage: usage, activity: activity)
        if signature != cachedSignature {
            cachedSignature = signature
            cachedContentWidth = DisplayPreferences.tools.map { tool in
                let probe = NSHostingView(rootView: CompactWing(
                    tool: tool, mirrored: false, stretch: false, usage: usage, activity: activity
                ).fixedSize())
                return probe.fittingSize.width.rounded(.up)
            }.max() ?? 0
        }
        return cachedContentWidth + edgePadding + Style.compactNotchGap
    }

    @MainActor
    private static func signature(usage: UsageStore, activity: ActivityStore) -> String {
        var parts = [String(describing: ContentPreferences.shared.values),
                     DisplayPreferences.shared.compactWindow.rawValue]
        for tool in DisplayPreferences.tools {
            let window = usage.usage(for: tool)?.window(for: DisplayPreferences.shared.compactWindow)
            parts.append(window?.label ?? "-")
            parts.append(window.map { String(Int($0.currentPercent.rounded())) } ?? "-")
            parts.append(window?.resetShortDescription ?? "-")
            parts.append("\(activity.count(for: tool, state: .working))/\(activity.count(for: tool, state: .needsInput))")
        }
        return parts.joined(separator: "|")
    }
}

/// Одне крило. `stretch` — розтягнути на всю ширину, притиснувши перший
/// елемент до зовнішнього краю, а решту — до вирізу; без нього крило має
/// власну ширину (так його й міряють).
private struct CompactWing: View {
    let tool: Tool
    let mirrored: Bool
    let stretch: Bool
    var usage: UsageStore
    var activity: ActivityStore

    /// Складові крила — в порядку для лівого крила, від зовнішнього краю до
    /// вирізу. Праве крило дзеркальне: мітка агента завжди на зовнішньому
    /// краї, а індикатор активності — впритул до вирізу.
    private enum Element: Hashable {
        case label, gauge, percent, windowTag, resetTime, activity, missing
    }

    var body: some View {
        let window = usage.usage(for: tool)?.window(for: DisplayPreferences.shared.compactWindow)
        let order = elements(hasWindow: window != nil)
        let outer = order.first
        let inner = Array(order.dropFirst())

        HStack(spacing: 5) {
            if mirrored {
                group(inner.reversed(), window: window)
                if stretch { Spacer(minLength: 0) }
                if let outer { view(for: outer, window: window) }
            } else {
                if let outer { view(for: outer, window: window) }
                if stretch { Spacer(minLength: 0) }
                group(inner, window: window)
            }
        }
    }

    private func group(_ elements: [Element], window: LimitWindow?) -> some View {
        HStack(spacing: 5) {
            ForEach(elements, id: \.self) { element in
                view(for: element, window: window)
            }
        }
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
    private func view(for element: Element, window: LimitWindow?) -> some View {
        let content = ContentPreferences.shared.values
        let stale = usage.usage(for: tool)?.isStale ?? true

        switch element {
        case .label:
            switch content.hoverLabel {
            case .logo:
                AgentLogo(tool: tool, size: 11)
            case .logoAndShort:
                HStack(spacing: 3) {
                    if mirrored { labelText(tool.shortName) }
                    AgentLogo(tool: tool, size: 11)
                    if !mirrored { labelText(tool.shortName) }
                }
            case .full:
                labelText(tool.displayName)
            case .short, .hidden:
                labelText(tool.shortName)
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

    private func labelText(_ text: String) -> some View {
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
