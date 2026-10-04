import SwiftUI

/// Знак агента, намальований векторно: у Claude — промениста «зірочка», у
/// Codex — хмаринка з підказкою терміналу `>_`. Власні контури замість
/// картинок із застосунків агентів: однаково чіткі на будь-якому розмірі й
/// не залежать від того, що встановлено на Mac.
struct AgentLogo: View {
    let tool: Tool
    var size: CGFloat = 11
    /// Колір знака; типово — фірмовий колір агента.
    var color: Color?

    var body: some View {
        let fill = color ?? Color(nsColor: tool.accent)
        Group {
            switch tool {
            case .claude:
                ClaudeSpark().fill(fill)
            case .codex:
                ZStack {
                    CodexCloud().fill(fill)
                    // Підказку вирізаємо з хмаринки, а не малюємо чорним — так
                    // крізь неї видно будь-яке тло.
                    CodexPrompt()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(tool.displayName)
    }
}

/// Промені різної довжини, що звужуються до заокруглених кінчиків.
private struct ClaudeSpark: Shape {
    /// Довжини променів відносно радіуса — нерівні, як у знаку Claude.
    private static let lengths: [CGFloat] = [1.0, 0.82, 0.95, 0.78, 1.0, 0.86, 0.92, 0.8, 0.98, 0.84, 0.9, 0.76]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let baseHalfWidth = radius * 0.15
        let tipHalfWidth = radius * 0.095
        let count = Self.lengths.count

        var path = Path()
        for (index, factor) in Self.lengths.enumerated() {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -direction.y, y: direction.x)
            let length = radius * factor - tipHalfWidth
            let tip = CGPoint(x: center.x + direction.x * length, y: center.y + direction.y * length)

            path.move(to: CGPoint(x: center.x + normal.x * baseHalfWidth, y: center.y + normal.y * baseHalfWidth))
            path.addLine(to: CGPoint(x: tip.x + normal.x * tipHalfWidth, y: tip.y + normal.y * tipHalfWidth))
            path.addArc(center: tip, radius: tipHalfWidth,
                        startAngle: .radians(Double(angle) + .pi / 2),
                        endAngle: .radians(Double(angle) - .pi / 2),
                        clockwise: true)
            path.addLine(to: CGPoint(x: center.x - normal.x * baseHalfWidth, y: center.y - normal.y * baseHalfWidth))
            path.closeSubpath()
        }
        // Серцевина, щоб основи променів зливалися в одне ціле.
        path.addEllipse(in: CGRect(x: center.x - baseHalfWidth * 1.4, y: center.y - baseHalfWidth * 1.4,
                                   width: baseHalfWidth * 2.8, height: baseHalfWidth * 2.8))
        return path
    }
}

/// Хмаринка з восьми пелюсток навколо круглої серцевини.
private struct CodexCloud: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let lobeRadius = radius * 0.36
        let orbit = radius - lobeRadius

        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - orbit, y: center.y - orbit, width: orbit * 2, height: orbit * 2))
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi + .pi / 8
            let lobe = CGPoint(x: center.x + cos(angle) * orbit, y: center.y + sin(angle) * orbit)
            path.addEllipse(in: CGRect(x: lobe.x - lobeRadius, y: lobe.y - lobeRadius,
                                       width: lobeRadius * 2, height: lobeRadius * 2))
        }
        return path
    }
}

/// Підказка терміналу `>_` усередині хмаринки.
private struct CodexPrompt: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * size, y: origin.y + y * size)
        }

        var path = Path()
        path.move(to: point(0.33, 0.37))
        path.addLine(to: point(0.44, 0.5))
        path.addLine(to: point(0.33, 0.63))
        path.move(to: point(0.52, 0.63))
        path.addLine(to: point(0.67, 0.63))
        return path
    }
}
