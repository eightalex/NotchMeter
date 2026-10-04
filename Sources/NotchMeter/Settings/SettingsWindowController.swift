import AppKit
import SwiftUI

/// Окреме вікно налаштувань. Одне на весь застосунок: повторний виклик лише
/// виводить його наперед.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var window: NSWindow?
    private var tabs: NSTabViewController?
    /// Відкриває вікно статистики — кнопка на вкладці «Статистика».
    var onOpenStats: (() -> Void)?

    enum Tab: Int {
        case general, appearance, stats
    }

    init(usage: UsageStore, activity: ActivityStore, onPreview: @escaping (NotchState?) -> Void) {
        model = SettingsModel(usage: usage, activity: activity, onPreview: onPreview)
        super.init()
    }

    /// Закріплений для перегляду стан потрібен, лише поки вікно відкрите.
    func windowWillClose(_ notification: Notification) {
        model.preview = .off
    }

    func show(tab: Tab? = nil) {
        model.syncLoginStatus()
        let window = self.window ?? makeWindow()
        self.window = window
        if let tab { tabs?.selectedTabViewItemIndex = tab.rawValue }

        // У застосунку немає іконки в Dock, тож без явної активації вікно
        // відкрилося б позаду поточного застосунку.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // Класичні для macOS вкладки-іконки на панелі інструментів; вікно
        // само підлаштовує розмір під обрану вкладку.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(
            title: "Загальні",
            symbol: "gearshape",
            view: GeneralSettingsView(model: model)
        ))
        tabs.addTabViewItem(tab(
            title: "Вигляд",
            symbol: "rectangle.topthird.inset.filled",
            view: AppearanceSettingsView(model: model, preferences: .shared, content: .shared)
        ))
        tabs.addTabViewItem(tab(
            title: "Статистика",
            symbol: "chart.bar.xaxis",
            view: StatsSettingsView(store: .shared, preferences: .shared) { [weak self] in self?.onOpenStats?() }
        ))
        self.tabs = tabs

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Центруємо вже за кінцевим розміром: інакше вікно центрується ще
        // крихітним і, вирісши, з'їжджає праворуч.
        window.setContentSize(tabs.tabViewItems.first?.viewController?.preferredContentSize ?? .zero)
        window.center()
        return window
    }

    private func tab<Content: View>(title: String, symbol: String, view: Content) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        hosting.title = title
        hosting.preferredContentSize = hosting.view.fittingSize
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}
