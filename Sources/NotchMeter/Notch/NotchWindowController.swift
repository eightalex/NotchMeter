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
    private var collapseWorkItem: DispatchWorkItem?
    private var cursorTimer: Timer?

    /// Невеликий запас навколо панелі, щоб курсор не «зривався» на межі.
    private let hoverPadding: CGFloat = 6
    private let expandedHoverPadding: CGFloat = 10

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

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackCursor() }
        }
        cursorTimer?.tolerance = 0.03
    }

    // MARK: - Побудова вікна

    private func rebuild() {
        guard let geometry = NotchGeometry.current() else { return }
        self.geometry = geometry

        let frame = geometry.windowFrame(sideWidth: Style.compactSideWidth, height: Style.compactHeight)

        let panel = self.panel ?? NotchPanel(contentRect: frame)
        let root = makeRootView(geometry: geometry)

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

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        applyState(animated: false)
    }

    private func makeRootView(geometry: NotchGeometry) -> NotchRootView {
        NotchRootView(geometry: geometry, usage: usage, activity: activity, state: state)
    }

    // MARK: - Розгортання

    private func setState(_ newState: NotchState) {
        guard !isSameState(state, newState) else { return }
        state = newState
        // Дані оновлюємо, щойно панель з'являється на очі.
        if case .hidden = newState {} else { usage.refreshAll() }
        applyState(animated: true)
    }

    private func isSameState(_ lhs: NotchState, _ rhs: NotchState) -> Bool {
        switch (lhs, rhs) {
        case (.hidden, .hidden), (.compact, .compact), (.expanded, .expanded): return true
        default: return false
        }
    }

    private func applyState(animated: Bool) {
        guard let panel, let geometry, let hostingView else { return }

        hostingView.rootView = makeRootView(geometry: geometry)
        // У спокої вікно прозоре для миші, щоб не перекривати рядок меню;
        // щойно з'явились індикатори — приймаємо клік, який розгортає панель.
        panel.ignoresMouseEvents = isHidden
        panel.hasShadow = isExpandedState

        let frame: CGRect
        switch state {
        case .hidden:
            // У спокої вікно завширшки рівно з вирізом, а коли хтось працює —
            // трохи ширше, рівно під крапки активності.
            frame = geometry.windowFrame(sideWidth: idleSideWidth, height: geometry.barHeight)
        case .compact:
            frame = geometry.windowFrame(sideWidth: Style.compactSideWidth, height: Style.compactHeight)
        case .expanded:
            let width = geometry.notchWidth + Style.expandedSideWidth * 2
            let height = measuredHeight(width: width, geometry: geometry)
            frame = CGRect(
                x: geometry.notchRect.midX - width / 2,
                y: geometry.notchRect.maxY - height,
                width: width,
                height: height
            )
        }

        if animated && !Style.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Висота панелі залежить від того, скільки зараз сесій і вікон лімітів.
    /// Міряємо на окремому view: у того, що вже на екрані, SwiftUI віддає
    /// розмір попереднього стану, і панель виходить обрізаною.
    private func measuredHeight(width: CGFloat, geometry: NotchGeometry) -> CGFloat {
        let probe = NSHostingView(rootView: makeRootView(geometry: geometry))
        probe.setFrameSize(NSSize(width: width, height: 0))
        probe.layoutSubtreeIfNeeded()
        let fitting = probe.fittingSize.height
        return min(max(fitting.rounded(.up), 150), 520)
    }

    // MARK: - Курсор

    /// Крила у спокої потрібні, лише поки є про що сигналити.
    private var idleSideWidth: CGFloat {
        guard activity.totalWorking + activity.totalNeedsInput > 0 else { return 0 }
        return Style.idleSideWidth(hasBadge: IdleView.hasBadge(in: activity))
    }

    private var isHidden: Bool {
        if case .hidden = state { return true }
        return false
    }

    private var isExpandedState: Bool {
        if case .expanded = state { return true }
        return false
    }

    private func trackCursor() {
        guard let panel, let geometry else { return }

        // У повноекранному режимі рядка меню немає — панель там зайва.
        let screen = geometry.screen
        let menuBarHidden = screen.visibleFrame.maxY >= screen.frame.maxY - 1
        if menuBarHidden {
            if panel.isVisible { panel.orderOut(nil) }
            return
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let location = NSEvent.mouseLocation
        let padding = isExpandedState ? expandedHoverPadding : hoverPadding
        // У спокої реагуємо на сам виріз, далі — на те, що вже намальовано.
        let base = isHidden ? geometry.notchRect : panel.frame
        let zone = base.insetBy(dx: -padding, dy: -padding)

        // У спокої ширина залежить від того, чи хтось працює просто зараз.
        if isHidden {
            let expected = geometry.windowFrame(sideWidth: idleSideWidth, height: geometry.barHeight)
            if abs(panel.frame.width - expected.width) > 0.5 {
                applyState(animated: true)
            }
        }

        if zone.contains(location) {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if isHidden { setState(.compact) }
        } else if !isHidden, collapseWorkItem == nil {
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

        menu.popUp(positioning: nil, at: point, in: container)
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
