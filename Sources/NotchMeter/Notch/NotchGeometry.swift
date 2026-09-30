import AppKit

/// Де саме на екрані розташований виріз і скільки місця є обабіч нього.
struct NotchGeometry {
    /// Прямокутник самого вирізу у координатах екрана (початок унизу зліва, як в AppKit).
    let notchRect: CGRect
    /// Чи це справжній виріз, чи ми лише імітуємо його на екрані без вирізу.
    let hasNotch: Bool
    let screen: NSScreen

    var notchWidth: CGFloat { notchRect.width }
    var barHeight: CGFloat { notchRect.height }

    /// Екран, обраний у налаштуваннях. Якщо обраний монітор від'єднано —
    /// поводимось як в автоматичному режимі.
    @MainActor
    static func preferredScreen() -> NSScreen? {
        switch DisplayPreferences.shared.screenChoice {
        case .automatic:
            break
        case .main:
            if let screen = NSScreen.screens.first { return screen }
        case let .display(uuid, _):
            if let screen = NSScreen.screens.first(where: { $0.displayUUID == uuid }) { return screen }
        }
        return automaticScreen()
    }

    /// Екран із вирізом, а якщо такого немає (зовнішній монітор із закритою
    /// кришкою) — той, де рядок меню. `NSScreen.main` не годиться: у
    /// застосунку без активного вікна ним легко стає зовнішній монітор, і
    /// панель переїжджала туди, лишаючи справжній виріз порожнім.
    static func automaticScreen() -> NSScreen? {
        NSScreen.screens.first(where: \.hasNotch) ?? NSScreen.screens.first
    }

    /// Висота рядка меню на екрані без вирізу. `NSStatusBar.thickness` тут
    /// не годиться: на великих зовнішніх моніторах рядок меню вищий (на LG
    /// Ultrafine — 30 pt проти 22), і виріз виходив помітно нижчим за нього.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        // Якщо рядок меню ховається автоматично, місця під нього не резервують.
        return reserved > 0 ? reserved : NSStatusBar.system.thickness
    }

    @MainActor
    static func current(for screen: NSScreen? = nil) -> NotchGeometry? {
        guard let screen = screen ?? preferredScreen() else { return nil }
        let frame = screen.frame

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            let rect = CGRect(
                x: frame.minX + left.maxX,
                y: frame.maxY - barHeight,
                width: right.minX - left.maxX,
                height: barHeight
            )
            return NotchGeometry(notchRect: rect, hasNotch: true, screen: screen)
        }

        // Зовнішній монітор: вирізу немає, тож лишаємо посередині порожнє місце
        // тієї ж ширини — компонування залишається тим самим.
        let custom = DisplayPreferences.shared.externalBarHeight
        let barHeight = custom > 0 ? CGFloat(custom) : menuBarHeight(on: screen)
        let width: CGFloat = 180
        let rect = CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - barHeight,
            width: width,
            height: barHeight
        )
        return NotchGeometry(notchRect: rect, hasNotch: false, screen: screen)
    }

    /// Рамка вікна для заданої ширини бічних крил і висоти вмісту.
    func windowFrame(sideWidth: CGFloat, height: CGFloat) -> CGRect {
        let width = notchWidth + sideWidth * 2
        return CGRect(
            x: notchRect.midX - width / 2,
            y: notchRect.maxY - height,
            width: width,
            height: height
        )
    }
}

extension NSScreen {
    var hasNotch: Bool {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return false }
        return right.minX > left.maxX
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Номер дисплея змінюється між перепідключеннями, а UUID — ні, тож
    /// обраний монітор запам'ятовуємо саме за ним.
    var displayUUID: String? {
        guard let id = displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
