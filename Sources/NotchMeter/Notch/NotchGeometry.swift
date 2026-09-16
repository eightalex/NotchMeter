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

    static func current(for screen: NSScreen? = nil) -> NotchGeometry? {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let frame = screen.frame
        let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
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
