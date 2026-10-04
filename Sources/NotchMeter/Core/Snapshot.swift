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
        let activity = FakeScanner.fromEnvironment().map { ActivityStore(scanners: $0) }
            ?? ActivityStore.makeDefault()
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

        if ProcessInfo.processInfo.environment["NOTCHMETER_SNAPSHOT_STATS"] != nil {
            await writeStats(to: directory)
        }
        writeStatusIcon(to: directory.appendingPathComponent("statusicon.png"))
        writeSettings(usage: usage, activity: activity, to: directory.appendingPathComponent("settings.png"))

        for (state, name) in [(NotchState.hidden, "idle"), (.compact, "compact"), (.expanded, "expanded")] {
            let metrics = NotchMetrics.make(
                for: state,
                geometry: geometry,
                idleSideWidth: idleSide,
                compactSideWidth: Style.compactSideWidth(badgeLength: IdleView.badgeLength(in: activity)),
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

        write(view: LogoSheet(), size: NSSize(width: 260, height: 110), backdrop: false,
              to: directory.appendingPathComponent("logos.png"))

        // `NOTCHMETER_SNAPSHOT_LOGOS=1` — ті самі стани з логотипами замість
        // CX/CC. Налаштування підміняємо лише на час рендеру.
        if ProcessInfo.processInfo.environment["NOTCHMETER_SNAPSHOT_LOGOS"] != nil {
            let original = ContentPreferences.shared.values
            defer { ContentPreferences.shared.values = original }
            for (style, suffix) in [(AgentLabelStyle.logo, "logo"), (.logoAndShort, "logo-short")] {
                ContentPreferences.shared.values.hoverLabel = style
                ContentPreferences.shared.values.panelShowsProviderLogo = true
                ContentPreferences.shared.values.panelSessionUsesLogo = true
                let height = ExpandedView.measuredHeight(
                    width: geometry.notchWidth + Style.expandedSideWidth * 2,
                    geometry: geometry, usage: usage, activity: activity
                )
                for (state, name) in [(NotchState.compact, "compact"), (.expanded, "expanded")] {
                    let metrics = NotchMetrics.make(
                        for: state, geometry: geometry, idleSideWidth: idleSide,
                        compactSideWidth: Style.compactSideWidth(badgeLength: IdleView.badgeLength(in: activity)),
                        expandedHeight: height
                    )
                    let size = NSSize(width: metrics.windowSize.width + 24, height: metrics.windowSize.height + 12)
                    write(
                        view: NotchRootView(geometry: geometry, usage: usage, activity: activity,
                                            state: state, metrics: metrics, animation: nil),
                        size: size, backdrop: true,
                        to: directory.appendingPathComponent("\(name)-\(suffix).png")
                    )
                }
            }
        }
    }

    /// Вкладки налаштувань — у справжньому вікні поза екраном: форма
    /// в стилі `.grouped` без вікна не малюється.
    private static func writeSettings(usage: UsageStore, activity: ActivityStore, to url: URL) {
        let model = SettingsModel(usage: usage, activity: activity) { _ in }
        let base = url.deletingPathExtension().lastPathComponent
        writeForm(GeneralSettingsView(model: model),
                  to: url.deletingLastPathComponent().appendingPathComponent("\(base)-general.png"))
        writeForm(AppearanceSettingsView(model: model, preferences: .shared, content: .shared),
                  to: url.deletingLastPathComponent().appendingPathComponent("\(base)-appearance.png"))
        writeForm(StatsSettingsView(store: .shared, preferences: .shared) {},
                  to: url.deletingLastPathComponent().appendingPathComponent("\(base)-stats.png"))
    }

    /// Вікно статистики з даними з бази. Довге — тож рендеримо на всю висоту
    /// вмісту, без прокрутки: `NOTCHMETER_SNAPSHOT_STATS=1`.
    private static func writeStats(to directory: URL) async {
        let store = StatsStore.shared
        store.start()
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !store.isImporting, store.lastImport != nil { break }
        }
        let view = StatsView(store: store, preferences: .shared, state: StatsViewState()) {}
        writeForm(view, to: directory.appendingPathComponent("stats.png"),
                  size: NSSize(width: 1040, height: 2600))
    }

    private static func writeForm<V: View>(_ view: V, to url: URL, size: NSSize? = nil) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = size == nil ? [.preferredContentSize] : []
        let window = NSWindow(contentViewController: hosting)
        if let size { window.setContentSize(size) }
        window.styleMask = [.titled, .closable]
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        // Даємо вікну кілька обертів циклу подій на верстку.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        window.layoutIfNeeded()

        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("вкладка налаштувань не намалювалась")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("записано \(url.path) — \(Int(view.bounds.width))×\(Int(view.bounds.height))")
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


/// Логотипи агентів великими й у справжньому розмірі.
private struct LogoSheet: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(Tool.allCases, id: \.self) { tool in
                AgentLogo(tool: tool, size: 64)
                AgentLogo(tool: tool, size: 11)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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

/// Вигадана активність для перевірки верстки, коли справжні агенти не
/// працюють: `NOTCHMETER_FAKE_ACTIVITY=codex,claude,claude` — по одній
/// сесії «в роботі» на кожну згадку, `claude!` — сесія, що чекає вводу.
private struct FakeScanner: SessionScanner {
    let tool: Tool
    let states: [AgentState]

    static func fromEnvironment() -> [FakeScanner]? {
        guard let raw = ProcessInfo.processInfo.environment["NOTCHMETER_FAKE_ACTIVITY"] else { return nil }
        var states: [Tool: [AgentState]] = [:]
        for item in raw.split(separator: ",") {
            let waiting = item.hasSuffix("!")
            guard let tool = Tool(rawValue: String(item.dropLast(waiting ? 1 : 0))) else { continue }
            states[tool, default: []].append(waiting ? .needsInput : .working)
        }
        return states.map { FakeScanner(tool: $0.key, states: $0.value) }
    }

    func scan() -> [AgentSession] {
        states.enumerated().map { index, state in
            AgentSession(id: "fake-\(tool.rawValue)-\(index)", tool: tool, title: "Вигадана сесія",
                         directory: "demo", state: state, since: Date(), steps: nil)
        }
    }
}
