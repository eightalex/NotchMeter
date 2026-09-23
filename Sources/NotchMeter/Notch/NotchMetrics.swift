import SwiftUI

/// Розміри чорної фігури в кожному стані. Саме між ними й відбувається
/// анімація: вікно лишається нерухомим, змінюється лише фігура всередині.
struct NotchMetrics: Equatable {
    /// Ширина «тіла» без вушок — у ній живе вміст.
    var bodyWidth: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Прозорий запас навколо фігури, щоб тінь не обрізалась краєм вікна.
    var shadowMargin: CGFloat

    var shapeWidth: CGFloat { bodyWidth + topRadius * 2 }

    var windowSize: CGSize {
        CGSize(width: shapeWidth + shadowMargin * 2, height: height + shadowMargin)
    }

    static func make(
        for state: NotchState,
        geometry: NotchGeometry,
        idleSideWidth: CGFloat,
        expandedHeight: CGFloat
    ) -> NotchMetrics {
        switch state {
        case .hidden where idleSideWidth == 0:
            // Рівно по вирізу: фігури не видно, але саме з неї все й виростає.
            return NotchMetrics(
                bodyWidth: geometry.notchWidth,
                height: geometry.barHeight,
                topRadius: 0,
                bottomRadius: Style.notchCorner,
                shadowMargin: 0
            )
        case .hidden:
            // Без вушок: у спокої фігура має бути не ширшою, ніж потрібно
            // крапкам, — вушка з'являються вже при наведенні.
            return NotchMetrics(
                bodyWidth: geometry.notchWidth + idleSideWidth * 2,
                height: geometry.barHeight,
                topRadius: 0,
                bottomRadius: Style.compactCorner,
                shadowMargin: 0
            )
        case .compact:
            return NotchMetrics(
                bodyWidth: geometry.notchWidth + Style.compactSideWidth * 2,
                height: Style.compactHeight,
                topRadius: Style.compactEar,
                bottomRadius: Style.compactCorner,
                shadowMargin: 0
            )
        case .expanded:
            return NotchMetrics(
                bodyWidth: geometry.notchWidth + Style.expandedSideWidth * 2,
                height: expandedHeight,
                topRadius: Style.expandedEar,
                bottomRadius: Style.expandedCorner,
                shadowMargin: Style.shadowMargin
            )
        }
    }

    /// Рамка вікна в координатах екрана: по центру вирізу, впритул до верху.
    func windowFrame(in geometry: NotchGeometry) -> CGRect {
        let size = windowSize
        return CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.notchRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Те, що користувач реально бачить, — без прозорого запасу під тінь.
    func visibleRect(in geometry: NotchGeometry) -> CGRect {
        CGRect(
            x: geometry.notchRect.midX - shapeWidth / 2,
            y: geometry.notchRect.maxY - height,
            width: shapeWidth,
            height: height
        )
    }
}

extension NotchState {
    /// Відкриття — з легким пружним «видихом», закриття — зібране й швидке.
    static func animation(from old: NotchState, to new: NotchState) -> Animation {
        if Style.reduceMotion { return .easeInOut(duration: 0.18) }
        switch (old, new) {
        case (.hidden, .compact):
            return .spring(response: 0.38, dampingFraction: 0.72)
        case (_, .expanded):
            return .spring(response: 0.46, dampingFraction: 0.76)
        case (.expanded, .compact):
            return .spring(response: 0.36, dampingFraction: 0.88)
        default:
            return .spring(response: 0.32, dampingFraction: 0.94)
        }
    }

    /// Зміни в межах одного стану: з'явилась крапка активності, додалась сесія.
    static var adjustmentAnimation: Animation {
        Style.reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.4, dampingFraction: 0.82)
    }
}
