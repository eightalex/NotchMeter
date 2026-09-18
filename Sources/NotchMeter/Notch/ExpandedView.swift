import SwiftUI

/// Панель, що «виростає» з-під вирізу: спершу квоти, потім те, чим агенти
/// зайняті просто зараз.
struct ExpandedView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Смуга заввишки з рядок меню — під нею ховається сам виріз.
            Color.clear.frame(height: geometry.barHeight)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(orderedUsage) { entry in
                    ProviderRow(entry: entry)
                }

                Divider().opacity(0.4)

                ActivitySection(activity: activity)

                if let updated = usage.lastUpdated {
                    Text("оновлено \(Self.clock.string(from: updated))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BottomRoundedShape(radius: Style.expandedCorner)
                .fill(Color.black)
        )

    }

    /// Той самий порядок, що й обабіч вирізу: лівий інструмент — першим.
    private var orderedUsage: [ProviderUsage] {
        let order = DisplayPreferences.shared.orderedTools
        return usage.usage.sorted {
            (order.firstIndex(of: $0.tool) ?? .max) < (order.firstIndex(of: $1.tool) ?? .max)
        }
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct ProviderRow: View {
    let entry: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: entry.tool.accent))
                if let plan = entry.planName {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.09), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if entry.isStale, !entry.windows.isEmpty {
                    Text("застаріло")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if entry.windows.isEmpty {
                Text(entry.error ?? "немає даних")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.windows) { window in
                    HStack(spacing: 8) {
                        Text(window.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)

                        GaugeBar(percent: window.usedPercent, stale: entry.isStale, width: 96, height: 4)

                        Text("\(Int(window.usedPercent.rounded()))%")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)

                        if let reset = window.resetDescription {
                            Text("· \(reset)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let error = entry.error {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(Style.warningColor)
                }
            }
        }
    }
}

private struct ActivitySection: View {
    var activity: ActivityStore

    var body: some View {
        // Звернення до tick прив'язує лічильники тривалості до секундного такту.
        let _ = activity.tick
        let sessions = activity.activeSessions

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Виконується")
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
                Text("Немає активних задач")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(6)) { session in
                    SessionRow(session: session)
                }
                if sessions.count > 6 {
                    Text("і ще \(sessions.count - 6)…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession

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

            Text(session.tool.shortName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)

            Text(session.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)

            Text("· \(session.directory)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(detail)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        var parts = [stateText]
        if let elapsed = session.elapsedDescription { parts.append(elapsed) }
        if let steps = session.steps, steps > 0 { parts.append("\(steps) кр.") }
        return parts.joined(separator: " · ")
    }
}

/// Верхні кути лишаємо прямими — панель має читатись як продовження рядка меню.
struct BottomRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)
        )
    }
}
