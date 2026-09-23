import AppKit
import SwiftUI

/// Малює обидва стани панелі у PNG без показу на екрані — так верстку можна
/// перевірити, не покладаючись на знімки екрана.
@MainActor
enum Snapshot {
    static func render(to directory: URL) async {
        guard let geometry = NotchGeometry.current() else {
            print("не вдалося визначити геометрію екрана")
            return
        }

        let usage = UsageStore.makeDefault()
        let activity = ActivityStore.makeDefault()
        usage.refreshAll()
        activity.scan()
        // Даємо провайдерам час відповісти — рендеримо зі справжніми даними.
        try? await Task.sleep(nanoseconds: 6_000_000_000)

        let expandedHeight = ExpandedView.measuredHeight(
            width: geometry.notchWidth + Style.expandedSideWidth * 2,
            geometry: geometry,
            usage: usage,
            activity: activity
        )
        let idleSide = activity.totalWorking + activity.totalNeedsInput > 0
            ? Style.idleSideWidth(badgeLength: IdleView.badgeLength(in: activity))
            : 0

        writeStatusIcon(to: directory.appendingPathComponent("statusicon.png"))

        for (state, name) in [(NotchState.hidden, "idle"), (.compact, "compact"), (.expanded, "expanded")] {
            let metrics = NotchMetrics.make(
                for: state,
                geometry: geometry,
                idleSideWidth: idleSide,
                expandedHeight: expandedHeight
            )
            // Трохи світлого поля довкола, щоб було видно вушка й тінь.
            let size = NSSize(width: metrics.windowSize.width + 24, height: metrics.windowSize.height + 12)
            write(
                view: NotchRootView(
                    geometry: geometry,
                    usage: usage,
                    activity: activity,
                    state: state,
                    metrics: metrics,
                    animation: nil
                ),
                size: size,
                backdrop: true,
                to: directory.appendingPathComponent("\(name).png")
            )
        }
    }

    /// Іконка рядка меню у 10-кратному збільшенні — на світлому й темному тлі,
    /// як її підфарбує система.
    private static func writeStatusIcon(to url: URL) {
        let icon = StatusItemController.makeIcon()
        let scale: CGFloat = 10
        let cell = NSSize(width: icon.size.width * scale + 40, height: icon.size.height * scale + 40)
        let canvas = NSImage(size: NSSize(width: cell.width * 2, height: cell.height))
        canvas.lockFocus()
        for (index, dark) in [false, true].enumerated() {
            let origin = NSPoint(x: CGFloat(index) * cell.width, y: 0)
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(origin: origin, size: cell).fill()

            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                (dark ? NSColor.white : NSColor.black).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: origin.x + 20, y: 20,
                                   width: icon.size.width * scale, height: icon.size.height * scale))
        }
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }

    /// `backdrop` домальовує темну підкладку: компактний вигляд живе на рядку
    /// меню, і на прозорому PNG його не видно.
    private static func write<V: View>(view: V, size: NSSize, backdrop: Bool, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        var target = size
        if target.height == 0 {
            hosting.setFrameSize(NSSize(width: size.width, height: 0))
            hosting.layoutSubtreeIfNeeded()
            target.height = max(hosting.fittingSize.height, 120)
        }
        hosting.setFrameSize(target)
        hosting.layoutSubtreeIfNeeded()

        // Панель завжди живе на темному тлі рядка меню біля вирізу.
        hosting.appearance = NSAppearance(named: .darkAqua)

        let canvas = BackdropView(frame: NSRect(origin: .zero, size: target))
        canvas.appearance = NSAppearance(named: .darkAqua)
        canvas.drawsBackdrop = backdrop
        canvas.addSubview(hosting)
        hosting.frame = canvas.bounds
        canvas.layoutSubtreeIfNeeded()

        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("записано \(url.path) — \(Int(target.width))×\(Int(target.height))")
    }
}


/// Світла підкладка імітує світлий рядок меню — найважчий для контрасту випадок.
private final class BackdropView: NSView {
    var drawsBackdrop = true

    override func draw(_ dirtyRect: NSRect) {
        guard drawsBackdrop else { return }
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        dirtyRect.fill()
    }
}
