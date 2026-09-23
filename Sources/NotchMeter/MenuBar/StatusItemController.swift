import AppKit

/// Іконка застосунку в рядку меню: той самий мотив, що й на іконці в Dock, —
/// дисплей із вирізом і дві шкали лімітів, — але контуром, як заведено для
/// рядка меню. Клік відкриває те саме меню, що й правий клік по панелі.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menuProvider: () -> NSMenu

    init(menuProvider: @escaping () -> NSMenu) {
        self.menuProvider = menuProvider
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.toolTip = "NotchMeter"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Пункти будуємо в момент відкриття, щоб позначки відповідали поточним
    /// налаштуванням.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = menuProvider()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    /// Малюємо кодом, а не з картинки: іконка лишається чіткою на будь-якому
    /// масштабі, а як шаблон сама підлаштовується під світлу й темну тему.
    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()

            // Дисплей.
            let frame = NSBezierPath(
                roundedRect: NSRect(x: 1.75, y: 1.75, width: 16.5, height: 12.5),
                xRadius: 3.2,
                yRadius: 3.2
            )
            frame.lineWidth = 1.5
            frame.stroke()

            // Виріз «вростає» у верхній край дисплея: згори він закінчується
            // рівно по зовнішньому краю контуру (y = 15), знизу — трохи нижче
            // за внутрішній.
            let notch = NSBezierPath()
            let notchRect = NSRect(x: 6.5, y: 11.6, width: 7, height: 3.4)
            let radius: CGFloat = 1.6
            notch.move(to: NSPoint(x: notchRect.minX, y: notchRect.maxY))
            notch.line(to: NSPoint(x: notchRect.minX, y: notchRect.minY + radius))
            notch.appendArc(
                from: NSPoint(x: notchRect.minX, y: notchRect.minY),
                to: NSPoint(x: notchRect.minX + radius, y: notchRect.minY),
                radius: radius
            )
            notch.line(to: NSPoint(x: notchRect.maxX - radius, y: notchRect.minY))
            notch.appendArc(
                from: NSPoint(x: notchRect.maxX, y: notchRect.minY),
                to: NSPoint(x: notchRect.maxX, y: notchRect.minY + radius),
                radius: radius
            )
            notch.line(to: NSPoint(x: notchRect.maxX, y: notchRect.maxY))
            notch.close()
            notch.fill()

            // Дві шкали: доріжка напівпрозора, заповнення — суцільне. Шаблон
            // зберігає прозорість, тож різниця лишається видимою.
            let track = NSRect(x: 4.75, y: 0, width: 10.5, height: 1.8)
            for (y, fill) in [(CGFloat(7.4), CGFloat(0.62)), (CGFloat(4.4), CGFloat(0.88))] {
                let rail = track.offsetBy(dx: 0, dy: y)
                NSColor.black.withAlphaComponent(0.35).set()
                NSBezierPath(roundedRect: rail, xRadius: 0.9, yRadius: 0.9).fill()

                var filled = rail
                filled.size.width = rail.width * fill
                NSColor.black.set()
                NSBezierPath(roundedRect: filled, xRadius: 0.9, yRadius: 0.9).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotchMeter"
        return image
    }
}
