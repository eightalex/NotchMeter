import SwiftUI

/// Панель, що «виростає» з-під вирізу: спершу квоти, потім те, чим агенти
/// зайняті просто зараз.
struct ExpandedView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        let content = ContentPreferences.shared.values
        let providers = orderedUsage.filter { content.panelShows($0.tool) }

        VStack(alignment: .leading, spacing: 0) {
            // Смуга заввишки з рядок меню — під нею ховається сам виріз.
            Color.clear.frame(height: geometry.barHeight)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(providers) { entry in
                    ProviderRow(entry: entry, content: content)
                }

                if !providers.isEmpty, content.panelShowsSessions {
                    Divider().opacity(0.4)
                }

                if content.panelShowsSessions {
                    ActivitySection(activity: activity, content: content)
                }

                TodayStatsLine()

                if content.panelShowsUpdatedAt, let updated = usage.lastUpdated {
                    Text("оновлено \(Self.clock.string(from: updated))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Той самий порядок, що й обабіч вирізу: лівий інструмент — першим.
    private var orderedUsage: [ProviderUsage] {
        let order = DisplayPreferences.shared.orderedTools
        return usage.usage.sorted {
            (order.firstIndex(of: $0.tool) ?? .max) < (order.firstIndex(of: $1.tool) ?? .max)
        }
    }

    /// Висота панелі залежить від кількості сесій і вікон лімітів. Міряємо на
    /// окремому view: фігура має знати кінцевий розмір ще до того, як почне
    /// рости, а вміст на екрані в цю мить ще старий.
    @MainActor
    static func measuredHeight(
        width: CGFloat,
        geometry: NotchGeometry,
        usage: UsageStore,
        activity: ActivityStore
    ) -> CGFloat {
        let probe = NSHostingView(rootView: ExpandedView(geometry: geometry, usage: usage, activity: activity))
        probe.setFrameSize(NSSize(width: width, height: 0))
        probe.layoutSubtreeIfNeeded()
        return min(max(probe.fittingSize.height.rounded(.up), 150), 520)
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// Підсумок дня зі статистики — якщо його ввімкнено в налаштуваннях.
private struct TodayStatsLine: View {
    var body: some View {
        let preferences = StatsPreferences.shared.values
        if preferences.panelShowsToday, preferences.recording,
           preferences.panelTodayTurns || preferences.panelTodayTime || preferences.panelTodayTokens {
            let analysis = StatsAnalysis(preferences: preferences)
            let today = analysis.interval(for: .today, earliest: nil)
            let turns = analysis.filter(StatsStore.shared.turns, in: today, tool: nil, project: nil)
            let summary = analysis.summary(turns, metric: .turns)

            HStack(spacing: 4) {
                Text("Сьогодні")
                    .font(.system(size: 10, weight: .semibold))
                Text(parts(summary, preferences: preferences).joined(separator: " · "))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func parts(_ summary: StatsAnalysis.Summary, preferences: StatsPreferences.Values) -> [String] {
        var parts: [String] = []
        if preferences.panelTodayTurns { parts.append("ходів \(summary.turns)") }
        if preferences.panelTodayTime { parts.append(StatsFormat.duration(summary.activeTime)) }
        if preferences.panelTodayTokens {
            parts.append("\(StatsFormat.number(Double(summary.countedTokens), style: .compact)) токенів")
        }
        return parts
    }
}

private struct ProviderRow: View {
    let entry: ProviderUsage
    let content: ContentPreferences.Values

    var body: some View {
        let windows = entry.windows.filter { content.panelShows($0.kind) }

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if content.panelShowsProviderLogo {
                    AgentLogo(tool: entry.tool, size: 13)
                }
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: entry.tool.accent))
                if content.panelShowsPlan, let plan = entry.planName {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.09), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if content.panelShowsStale, entry.isStale, !entry.windows.isEmpty {
                    Text("застаріло")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if entry.windows.isEmpty {
                Text(content.panelShowsErrors ? (entry.error ?? "немає даних") : "немає даних")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(windows) { window in
                    windowRow(window)
                }

                if content.panelShowsErrors, let error = entry.error {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(Style.warningColor)
                }
            }
        }
    }

    private func windowRow(_ window: LimitWindow) -> some View {
        let shown = content.panelPercentMode.value(fromUsed: window.currentPercent)
        return HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            if content.panelShowsGauge {
                GaugeBar(
                    percent: shown,
                    stale: entry.isStale,
                    width: CGFloat(content.panelGaugeWidth),
                    height: 4,
                    usedPercent: window.currentPercent,
                    tint: content.panelGaugeColoring == .accent ? Color(nsColor: entry.tool.accent) : nil
                )
            }

            Text("\(Int(shown.rounded()))%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .frame(width: 32, alignment: .trailing)

            if let reset = resetText(window) {
                Text("· \(reset)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func resetText(_ window: LimitWindow) -> String? {
        // Після скидання точний час уже нічого не каже — лише «скинуто».
        if window.hasReset { return content.panelResetFormat == .hidden ? nil : window.resetDescription }
        switch content.panelResetFormat {
        case .relative:
            return window.resetDescription
        case .absolute:
            return window.resetAbsoluteDescription
        case .both:
            guard let relative = window.resetDescription else { return nil }
            guard let absolute = window.resetAbsoluteDescription else { return relative }
            return "\(relative) (\(absolute))"
        case .hidden:
            return nil
        }
    }
}

private struct ActivitySection: View {
    var activity: ActivityStore
    let content: ContentPreferences.Values

    var body: some View {
        // Звернення до tick прив'язує лічильники тривалості до секундного такту.
        let _ = activity.tick
        let sessions = activity.panelSessions(includingIdle: content.panelIncludesIdleSessions)
        let limit = max(1, content.panelMaxSessions)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(content.panelIncludesIdleSessions ? "Сесії" : "Виконується")
                    .font(.system(size: 11, weight: .semibold))
                if !sessions.isEmpty {
                    Text("\(sessions.count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }

            if sessions.isEmpty {
                Text(content.panelIncludesIdleSessions ? "Немає відкритих сесій" : "Немає активних задач")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(limit)) { session in
                    SessionRow(session: session, content: content)
                }
                if sessions.count > limit {
                    Text("і ще \(sessions.count - limit)…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let content: ContentPreferences.Values

    private var color: Color {
        Color(nsColor: session.tool.accent)
    }

    private var stateText: String {
        switch session.state {
        case .working: return "працює"
        case .needsInput: return "чекає вводу"
        case .idle: return "простій"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: session.state == .needsInput ? 1 : 0)
                )
                .frame(width: 5, height: 5)

            if content.panelSessionUsesLogo {
                AgentLogo(tool: session.tool, size: 10)
            } else {
                Text(session.tool.shortName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }

            if content.panelSessionShowsTitle {
                Text(session.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if content.panelSessionShowsDirectory {
                Text(content.panelSessionShowsTitle ? "· \(session.directory)" : session.directory)
                    .font(.system(size: content.panelSessionShowsTitle ? 9 : 10))
                    .foregroundStyle(content.panelSessionShowsTitle ? .tertiary : .primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let detail {
                Text(detail)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if content.panelSessionShowsState { parts.append(stateText) }
        if content.panelSessionShowsElapsed, let elapsed = session.elapsedDescription { parts.append(elapsed) }
        if content.panelSessionShowsSteps, let steps = session.steps, steps > 0 { parts.append("\(steps) кр.") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
