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

        let idleWidth = geometry.notchWidth + Style.idleSideWidth(hasBadge: IdleView.hasBadge(in: activity)) * 2
        write(
            view: NotchRootView(geometry: geometry, usage: usage, activity: activity, state: .hidden),
            size: NSSize(width: idleWidth, height: Style.compactHeight),
            backdrop: true,
            to: directory.appendingPathComponent("idle.png")
        )

        let compactWidth = geometry.notchWidth + Style.compactSideWidth * 2
        write(
            view: NotchRootView(geometry: geometry, usage: usage, activity: activity, state: .compact),
            size: NSSize(width: compactWidth, height: Style.compactHeight),
            backdrop: true,
            to: directory.appendingPathComponent("compact.png")
        )

        let expandedWidth = geometry.notchWidth + Style.expandedSideWidth * 2
        write(
            view: NotchRootView(geometry: geometry, usage: usage, activity: activity, state: .expanded),
            size: NSSize(width: expandedWidth, height: 0),
            backdrop: false,
            to: directory.appendingPathComponent("expanded.png")
        )
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
