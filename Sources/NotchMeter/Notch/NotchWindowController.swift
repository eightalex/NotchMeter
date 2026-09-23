import AppKit
import ServiceManagement
import SwiftUI

/// Тримає панель на місці, стежить за курсором і вирішує, коли розгортатись.
@MainActor
final class NotchWindowController: NSObject {
    private let usage: UsageStore
    private let activity: ActivityStore

    private var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchRootView>?
    private var container: EventCatcherView?
    private var geometry: NotchGeometry?

    private var state: NotchState = .hidden
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

        if state == .hidden, targetMetrics(geometry: geometry) != metrics {
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
        setState(isExpandedState ? .compact : .expanded)
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
    /// Щоразу будується наново, щоб позначки відповідали поточним налаштуванням.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Оновити зараз", action: #selector(refreshNow), keyEquivalent: "")
            .target = self

        let intervals = NSMenu()
        for (title, multiplier) in [("Звичайний", 1.0), ("Удвічі рідше", 2.0), ("Уп'ятеро рідше", 5.0)] {
            let item = NSMenuItem(title: title, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = multiplier
            item.state = Settings.refreshMultiplier == multiplier ? .on : .off
            intervals.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Частота оновлення", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.addItem(intervalItem)

        let prefs = DisplayPreferences.shared

        let sides = NSMenu()
        for left in DisplayPreferences.tools {
            let right = DisplayPreferences.tools.first { $0 != left } ?? left
            let title = "\(left.displayName) ліворуч, \(right.displayName) праворуч"
            let item = NSMenuItem(title: title, action: #selector(changeLeftTool(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = left.rawValue
            item.state = prefs.leftTool == left ? .on : .off
            sides.addItem(item)
        }
        let sidesItem = NSMenuItem(title: "Розташування", action: nil, keyEquivalent: "")
        sidesItem.submenu = sides
        menu.addItem(sidesItem)

        let windows = NSMenu()
        for choice in CompactWindowChoice.allCases {
            let item = NSMenuItem(title: choice.menuTitle, action: #selector(changeCompactWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = prefs.compactWindow == choice ? .on : .off
            windows.addItem(item)
        }
        let windowsItem = NSMenuItem(title: "Ліміт в індикаторі", action: nil, keyEquivalent: "")
        windowsItem.submenu = windows
        menu.addItem(windowsItem)

        let loginItem = NSMenuItem(title: "Запускати при вході", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Вийти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func refreshNow() {
        usage.refreshAll(force: true)
        activity.scan()
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let multiplier = sender.representedObject as? Double else { return }
        Settings.refreshMultiplier = multiplier
        usage.start()
    }

    @objc private func changeLeftTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tool = Tool(rawValue: raw) else { return }
        DisplayPreferences.shared.leftTool = tool
    }

    @objc private func changeCompactWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = CompactWindowChoice(rawValue: raw) else { return }
        DisplayPreferences.shared.compactWindow = choice
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
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
