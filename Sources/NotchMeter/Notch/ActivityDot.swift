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
            HStack(spacing: 2) {
                // «Чекає на тебе» важливіше за «зайнятий»: кільце лишається,
                // доки хоч одна сесія чекає відповіді.
                PulsingDot(color: color, pulsing: shouldPulse, ringed: needsInput > 0, diameter: 6)
                    .frame(width: 6, height: 6)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(nsColor: color))
                }
            }
        }
    }
}

/// Пульсація живе на рівні Core Animation: вона не залежить від оновлень
/// даних і не змушує SwiftUI перемальовувати панель кожен кадр.
struct PulsingDot: NSViewRepresentable {
    let color: NSColor
    let pulsing: Bool
    var ringed = false
    let diameter: CGFloat

    func makeNSView(context: Context) -> DotView {
        let view = DotView(diameter: diameter)
        view.apply(color: color, pulsing: pulsing, ringed: ringed)
        return view
    }

    func updateNSView(_ nsView: DotView, context: Context) {
        nsView.apply(color: color, pulsing: pulsing, ringed: ringed)
    }

    final class DotView: NSView {
        private let dot = CALayer()
        private var currentColor: NSColor?
        private var isPulsing = false

        init(diameter: CGFloat) {
            super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            wantsLayer = true
            dot.cornerRadius = diameter / 2
            layer?.addSublayer(dot)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) не підтримується") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.frame = bounds
            dot.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }

        func apply(color: NSColor, pulsing: Bool, ringed: Bool) {
            if currentColor != color {
                currentColor = color
                dot.backgroundColor = color.cgColor
            }
            dot.borderColor = NSColor.white.cgColor
            dot.borderWidth = ringed ? 1.5 : 0
            guard isPulsing != pulsing else { return }
            isPulsing = pulsing

            if pulsing {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 1.0
                animation.toValue = 0.3
                animation.duration = 0.9
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(animation, forKey: "pulse")
            } else {
                dot.removeAnimation(forKey: "pulse")
                dot.opacity = 1
            }
        }
    }
}
