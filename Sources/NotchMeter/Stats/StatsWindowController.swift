import AppKit
import SwiftUI

/// Окреме вікно статистики. Одне на весь застосунок.
@MainActor
final class StatsWindowController: NSObject, NSWindowDelegate {
    private let store: StatsStore
    private let state = StatsViewState()
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(store: StatsStore? = nil, openSettings: @escaping () -> Void) {
        self.store = store ?? .shared
        self.openSettings = openSettings
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // Свіжі ходи з'являються одразу, а не з наступним хвилинним імпортом.
        store.importNow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = StatsView(store: store, preferences: .shared, state: state, openSettings: openSettings)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Статистика"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 1040, height: 820))
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.setFrameAutosaveName("NotchMeterStats")
        if !window.setFrameUsingName("NotchMeterStats") { window.center() }
        return window
    }
}
