import SwiftUI

/// Що саме показує панель просто зараз.
enum NotchState {
    /// Виріз лишається чистим — жодних слідів застосунку.
    case hidden
    /// Курсор над вирізом: короткі індикатори обабіч нього.
    case compact
    /// Після кліку: повна панель із лімітами та сесіями.
    case expanded
}

struct NotchRootView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore
    var state: NotchState

    var body: some View {
        ZStack(alignment: .top) {
            switch state {
            case .hidden:
                IdleView(geometry: geometry, activity: activity)
                    .transition(.opacity)
            case .compact:
                CompactView(geometry: geometry, usage: usage, activity: activity)
                    .transition(.opacity)
            case .expanded:
                ExpandedView(geometry: geometry, usage: usage, activity: activity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Панель завжди темна — як і виріз, до якого вона прилягає.
        .environment(\.colorScheme, .dark)
        .animation(Style.reduceMotion ? nil : .easeOut(duration: 0.16), value: isVisible)
    }

    private var isVisible: Bool {
        if case .hidden = state { return false }
        return true
    }
}
