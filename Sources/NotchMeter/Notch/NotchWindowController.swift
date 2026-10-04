import AppKit
import SwiftUI

/// Тримає панель на місці, стежить за курсором і вирішує, коли розгортатись.
@MainActor
final class NotchWindowController: NSObject {
    private let usage: UsageStore
    private let activity: ActivityStore

    /// Відкриває вікно налаштувань — його тримає делегат застосунку.
    var onOpenSettings: (() -> Void)?
    var onOpenStats: (() -> Void)?

    private var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchRootView>?
    private var container: EventCatcherView?
    private var geometry: NotchGeometry?

    private var state: NotchState = .hidden
    /// Стан, закріплений із налаштувань для перегляду: поки він є, курсор і
    /// кліки стан не змінюють.
    private var pinnedState: NotchState?
    /// Розміри фігури, до яких вона зараз прямує (або вже досягла).
    private var metrics: NotchMetrics?
    private var expandedHeight: CGFloat = 200

    private var collapseWorkItem: DispatchWorkItem?
    private var settleWorkItem: DispatchWorkItem?
    private var cursorTimer: Timer?
    private var mouseMonitors: [Any] = []
    private var ticks = 0

    /// Невеликий запас навколо панелі, щоб курсор не «зривався» на межі.
    private let hoverPadding: CGFloat = 6
    private let expandedHoverPadding: CGFloat = 10
    /// Скільки чекати, доки пружина вгамується, перш ніж підрізати вікно.
    private let settleDelay: TimeInterval = 0.75

    init(usage: UsageStore, activity: ActivityStore) {
        self.usage = usage
        self.activity = activity
        super.init()
    }

    func start() {
        rebuild()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        installMouseMonitors()

        // Рух миші ловлять монітори подій; таймер лише підстраховує і
        // стежить за тим, що від миші не залежить (крапки, повний екран).
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        cursorTimer?.tolerance = 0.05
    }

    /// Реакція на наведення без затримки опитування — саме від неї залежить,
    /// чи відчувається анімація «живою».
    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            Task { @MainActor in self?.trackCursor() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            Task { @MainActor in self?.trackCursor() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    // MARK: - Побудова вікна

    private func rebuild() {
        guard let geometry = NotchGeometry.current() else { return }
        self.geometry = geometry

        let target = targetMetrics(geometry: geometry)
        let frame = target.windowFrame(in: geometry)

        let panel = self.panel ?? NotchPanel(contentRect: frame)
        panel.acceptsMouseMovedEvents = true
        let root = makeRootView(geometry: geometry, metrics: target, animation: nil)

        if let hostingView {
            hostingView.rootView = root
        } else {
            let hostingView = NSHostingView(rootView: root)
            hostingView.appearance = NSAppearance(named: .darkAqua)
            hostingView.translatesAutoresizingMaskIntoConstraints = true
            hostingView.autoresizingMask = [.width, .height]

            let container = EventCatcherView(frame: CGRect(origin: .zero, size: frame.size))
            container.appearance = NSAppearance(named: .darkAqua)
            container.autoresizingMask = [.width, .height]
            container.onRightClick = { [weak self] point in self?.showMenu(at: point) }
            container.onClick = { [weak self] in self?.toggleExpanded() }
            container.addSubview(hostingView)
            hostingView.frame = container.bounds

            panel.contentView = container
            self.hostingView = hostingView
            self.container = container
        }

        settleWorkItem?.cancel()
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = state == .hidden
        panel.orderFrontRegardless()
        self.panel = panel
        metrics = target
    }

    private func makeRootView(geometry: NotchGeometry, metrics: NotchMetrics, animation: Animation?) -> NotchRootView {
        NotchRootView(
            geometry: geometry,
            usage: usage,
            activity: activity,
            state: state,
            metrics: metrics,
            animation: animation
        )
    }

    private func targetMetrics(geometry: NotchGeometry) -> NotchMetrics {
        NotchMetrics.make(
            for: state,
            geometry: geometry,
            idleSideWidth: idleSideWidth,
            compactSideWidth: CompactView.sideWidth(usage: usage, activity: activity),
            expandedHeight: expandedHeight
        )
    }

    // MARK: - Перехід між станами

    private func setState(_ newState: NotchState) {
        guard state != newState else { return }
        let old = state
        state = newState
        // Дані оновлюємо, щойно панель з'являється на очі.
        if newState != .hidden { usage.refreshAll() }
        if newState == .expanded { remeasureExpandedHeight() }
        applyState(animation: NotchState.animation(from: old, to: newState))
    }

    /// Вікно не анімується: спершу воно одразу стає достатньо великим для
    /// всього руху, потім фігура всередині плавно змінює розмір, а коли
    /// пружина вгамується — вікно підрізається до кінцевого розміру.
    /// Вміст прив'язаний до верху по центру, тож зміна вікна на око непомітна.
    private func applyState(animation: Animation?) {
        guard let panel, let geometry, let hostingView else { return }

        let target = targetMetrics(geometry: geometry)
        let targetFrame = target.windowFrame(in: geometry)

        settleWorkItem?.cancel()
        settleWorkItem = nil

        if animation != nil {
            // Поточна рамка вже вміщує фігуру в польоті; запас під пружину
            // додаємо лише до цілі, інакше при частих переходах вікно росло б.
            var slackTarget = targetFrame.insetBy(dx: -Style.springSlack, dy: 0)
            slackTarget.origin.y -= Style.springSlack
            slackTarget.size.height += Style.springSlack
            panel.setFrame(panel.frame.union(slackTarget), display: false)
        }

        // У спокої вікно прозоре для миші, щоб не перекривати рядок меню;
        // щойно з'явились індикатори — приймаємо клік, який розгортає панель.
        panel.ignoresMouseEvents = state == .hidden
        hostingView.rootView = makeRootView(geometry: geometry, metrics: target, animation: animation)
        metrics = target

        guard animation != nil else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                self.settleWorkItem = nil
                panel.setFrame(targetFrame, display: true)
            }
        }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: item)
    }

    private func remeasureExpandedHeight() {
        guard let geometry else { return }
        expandedHeight = ExpandedView.measuredHeight(
            width: geometry.notchWidth + Style.expandedSideWidth * 2,
            geometry: geometry,
            usage: usage,
            activity: activity
        )
    }

    // MARK: - Курсор

    /// Крила у спокої потрібні, лише поки є про що сигналити.
    private var idleSideWidth: CGFloat {
        guard activity.totalWorking + activity.totalNeedsInput > 0 else { return 0 }
        return Style.idleSideWidth(badgeLength: IdleView.badgeLength(in: activity))
    }

    private var isExpandedState: Bool { state == .expanded }

    /// Те, від чого не залежить рух миші: чи не з'явилась крапка активності,
    /// чи не змінилась кількість сесій у розгорнутій панелі.
    private func heartbeat() {
        ticks += 1
        trackCursor()
        guard let geometry else { return }

        // Рядок меню міг змінити висоту, а в налаштуваннях — висоту вирізу на
        // зовнішньому моніторі. Окремого сповіщення про це немає.
        if ticks % 4 == 0, let fresh = NotchGeometry.current(),
           fresh.notchRect != geometry.notchRect || fresh.screen.displayID != geometry.screen.displayID {
            rebuild()
            return
        }

        // У спокої й при наведенні розмір залежить від активності та від
        // увімкненого в налаштуваннях вмісту — підлаштовуємось на ходу.
        if state != .expanded, targetMetrics(geometry: geometry) != metrics {
            applyState(animation: NotchState.adjustmentAnimation)
        }

        // Раз на секунду звіряємо висоту панелі з тим, що в ній зараз є.
        if state == .expanded, ticks % 4 == 0 {
            let previous = expandedHeight
            remeasureExpandedHeight()
            if abs(previous - expandedHeight) > 1 {
                applyState(animation: NotchState.adjustmentAnimation)
            }
        }
    }

    private func trackCursor() {
        guard let panel, let geometry, let metrics else { return }

        // У повноекранному режимі рядка меню немає — панель там зайва.
        let screen = geometry.screen
        let menuBarHidden = screen.visibleFrame.maxY >= screen.frame.maxY - 1
        if menuBarHidden {
            if panel.isVisible { panel.orderOut(nil) }
            return
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        // Зона наведення — те, що видно, а не все вікно разом із запасом під тінь.
        let location = NSEvent.mouseLocation
        let visible = metrics.visibleRect(in: geometry)
        let padding = isExpandedState ? expandedHoverPadding : hoverPadding
        let zone = visible.insetBy(dx: -padding, dy: -padding)

        // Кліки приймаємо лише над самою фігурою: прозорий запас під тінь і
        // пружину не має перехоплювати кліки, адресовані вікнам під ним.
        let catchesClicks = state != .hidden && visible.contains(location)
        if panel.ignoresMouseEvents == catchesClicks {
            panel.ignoresMouseEvents = !catchesClicks
        }

        // Закріплений для перегляду стан курсор не змінює.
        guard pinnedState == nil else { return }

        if zone.contains(location) {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if state == .hidden { setState(.compact) }
        } else if state != .hidden, collapseWorkItem == nil {
            scheduleCollapse()
        }
    }

    /// Затримка перед згортанням, щоб панель не блимала при швидкому русі миші.
    private func scheduleCollapse() {
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.collapseWorkItem = nil
                self.setState(.hidden)
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func toggleExpanded() {
        guard pinnedState == nil else { return }
        setState(isExpandedState ? .compact : .expanded)
    }

    /// Тримати виріз у заданому стані, щоб зміни в налаштуваннях було видно
    /// одразу, без наведення й кліків. `nil` — повернутися до звичайної
    /// поведінки.
    func pin(_ state: NotchState?) {
        pinnedState = state
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        setState(state ?? .hidden)
        // Якщо курсор якраз над вирізом, стан одразу відповідатиме йому.
        if state == nil { trackCursor() }
    }

    // MARK: - Події системи

    @objc private func screenParametersChanged() {
        rebuild()
    }

    @objc private func systemDidWake() {
        usage.refreshAll()
        activity.scan()
    }

    // MARK: - Меню

    private func showMenu(at point: NSPoint) {
        guard let container else { return }
        makeMenu().popUp(positioning: nil, at: point, in: container)
    }

    /// Одне меню на два входи: правий клік по панелі та іконка в рядку меню.
    /// Самі налаштування живуть в окремому вікні; тут — лише шлях до нього
    /// та вихід, бо іконки в Dock у застосунку немає.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let stats = NSMenuItem(title: "Статистика…", action: #selector(openStats), keyEquivalent: "s")
        stats.target = self
        menu.addItem(stats)

        let settings = NSMenuItem(title: "Налаштування…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Вийти з NotchMeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openStats() {
        onOpenStats?()
    }
}

/// Контейнер, що ловить правий клік для контекстного меню.
final class EventCatcherView: NSView {
    var onRightClick: ((NSPoint) -> Void)?
    var onClick: (() -> Void)?

    // Панель не стає активним вікном, тож без цього перший клік губився б.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(convert(event.locationInWindow, from: nil))
        } else {
            onClick?()
        }
    }
}
