import SwiftUI

/// Силует панелі: знизу заокруглений, а зверху — з увігнутими «вушками»,
/// якими фігура плавно відходить від краю екрана, ніби витікає з вирізу.
///
/// Обидва радіуси анімуються, тож при переході між станами фігура саме
/// перетікає, а не перемикається.
struct NotchShape: Shape {
    /// Ширина увігнутого вушка з кожного боку; фігура займає `rect` разом із ним.
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Під час пружини розміри на мить бувають дуже малими — не даємо
        // радіусам вийти за межі фігури.
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bodyWidth = rect.width - top * 2
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, rect.height - top))

        let left = rect.minX + top
        let right = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        if top > 0 {
            path.addArc(
                tangent1End: CGPoint(x: left, y: rect.minY),
                tangent2End: CGPoint(x: left, y: rect.minY + top),
                radius: top
            )
        } else {
            path.addLine(to: CGPoint(x: left, y: rect.minY))
        }

        path.addArc(
            tangent1End: CGPoint(x: left, y: rect.maxY),
            tangent2End: CGPoint(x: left + bottom, y: rect.maxY),
            radius: bottom
        )
        path.addArc(
            tangent1End: CGPoint(x: right, y: rect.maxY),
            tangent2End: CGPoint(x: right, y: rect.maxY - bottom),
            radius: bottom
        )

        if top > 0 {
            path.addArc(
                tangent1End: CGPoint(x: right, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                radius: top
            )
        } else {
            path.addLine(to: CGPoint(x: right, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
