import AppKit
import SwiftUI

/// Показує, чи виконується зараз задача цим інструментом, і скільки сесій
/// працює одночасно. Коли все спокійно — нічого не малюємо.
struct ActivityDot: View {
    let tool: Tool
    let working: Int
    let needsInput: Int

    private var isVisible: Bool { working > 0 || needsInput > 0 }

    private var color: NSColor { tool.accent }

    /// Пульсує лише «в роботі»: очікування вводу має читатись як стабільний стан.
    private var shouldPulse: Bool {
        needsInput == 0 && working > 0 && !Style.reduceMotion
    }

    private var badge: String? { Self.badge(working: working, needsInput: needsInput) }

    /// `2/1` — двоє працюють, один чекає відповіді.
    static func badge(working: Int, needsInput: Int) -> String? {
        if working > 0 && needsInput > 0 { return "\(working)/\(needsInput)" }
        if working > 1 { return "\(working)" }
        if needsInput > 1 { return "\(needsInput)" }
        return nil
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 0) {
                // «Чекає на тебе» важливіше за «зайнятий»: кільце лишається,
                // доки хоч одна сесія чекає відповіді.
                PulsingDot(color: color, pulsing: shouldPulse, ringed: needsInput > 0)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(nsColor: color))
                }
            }
            .fixedSize()
        }
    }
}

/// Пульсація живе на рівні Core Animation: сервер рендерингу крутить її сам,
/// і застосунок не перемальовує панель на кожному кадрі (аналог на SwiftUI
/// коштував близько 8 % CPU проти десятих часток відсотка тут).
struct PulsingDot: NSViewRepresentable {
    static let diameter: CGFloat = 6
    /// Прозорий запас довкола кола: коли AppKit вирівнює шар по пікселях,
    /// коло впритул до меж шару втрачало крайній піксель — звідси «обрізання».
    static let padding: CGFloat = 1
    static var side: CGFloat { diameter + padding * 2 }

    let color: NSColor
    let pulsing: Bool
    var ringed = false

    func makeNSView(context: Context) -> DotView {
        let view = DotView()
        view.apply(color: color, pulsing: pulsing, ringed: ringed)
        return view
    }

    func updateNSView(_ nsView: DotView, context: Context) {
        nsView.apply(color: color, pulsing: pulsing, ringed: ringed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotView, context: Context) -> CGSize? {
        CGSize(width: Self.side, height: Self.side)
    }

    final class DotView: NSView {
        private let dot = CALayer()
        private var currentColor: NSColor?
        private var isPulsing = false

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: PulsingDot.side, height: PulsingDot.side))
            wantsLayer = true
            layer?.masksToBounds = false
            dot.cornerRadius = PulsingDot.diameter / 2
            dot.borderColor = NSColor.white.cgColor
            layer?.addSublayer(dot)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) не підтримується") }

        override var intrinsicContentSize: NSSize {
            NSSize(width: PulsingDot.side, height: PulsingDot.side)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Коло завжди по центру власного розміру, а не на весь шар.
            let d = PulsingDot.diameter
            dot.frame = CGRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
            CATransaction.commit()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            dot.contentsScale = window?.backingScaleFactor ?? 2
        }

        /// Шар губить анімації, коли view виймають із вікна, — повертаємо.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, isPulsing, dot.animation(forKey: "pulse") == nil {
                addPulse()
            }
        }

        func apply(color: NSColor, pulsing: Bool, ringed: Bool) {
            if currentColor != color {
                currentColor = color
                dot.backgroundColor = color.cgColor
            }
            dot.borderWidth = ringed ? 1.5 : 0
            guard isPulsing != pulsing else { return }
            isPulsing = pulsing

            if pulsing {
                addPulse()
            } else {
                dot.removeAnimation(forKey: "pulse")
                dot.opacity = 1
            }
        }

        private func addPulse() {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.3
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(animation, forKey: "pulse")
        }
    }
}
