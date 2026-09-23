import SwiftUI

/// Що саме показує панель просто зараз.
enum NotchState {
    /// Біля вирізу — лише крапки активності, а коли всі мовчать, то й їх немає.
    case hidden
    /// Курсор над вирізом: короткі індикатори обабіч нього.
    case compact
    /// Після кліку: повна панель із лімітами та сесіями.
    case expanded
}

/// Одна чорна фігура на всі стани. Вона не змінюється стрибком, а плавно
/// перетікає з розміру в розмір, а вміст проявляється вже всередині неї.
struct NotchRootView: View {
    let geometry: NotchGeometry
    var usage: UsageStore
    var activity: ActivityStore
    var state: NotchState
    var metrics: NotchMetrics
    /// Анімація переходу, яку обрав контролер: відкриття й закриття різняться.
    var animation: Animation?

    var body: some View {
        let shape = NotchShape(topRadius: metrics.topRadius, bottomRadius: metrics.bottomRadius)

        ZStack(alignment: .top) {
            // Тінь малюємо окремим шаром: вміст обрізаний формою, а тінь має
            // виходити за її межі.
            shape
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(state == .expanded ? 0.55 : 0),
                    radius: 18,
                    y: 10
                )

            content
                .padding(.horizontal, metrics.topRadius)
                .frame(width: metrics.shapeWidth, height: metrics.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: metrics.shapeWidth, height: metrics.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Панель завжди темна — як і виріз, до якого вона прилягає.
        .environment(\.colorScheme, .dark)
        .animation(animation, value: metrics)
        .animation(animation, value: state)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            IdleView(geometry: geometry, activity: activity)
                .transition(.notchContent(blur: 3, offset: 0, delay: 0.04))
        case .compact:
            CompactView(geometry: geometry, usage: usage, activity: activity)
                .transition(.notchContent(blur: 5, offset: 0, delay: 0.06))
        case .expanded:
            ExpandedView(geometry: geometry, usage: usage, activity: activity)
                .transition(.notchContent(blur: 8, offset: -10, delay: 0.1))
        }
    }
}

extension AnyTransition {
    /// Вміст проявляється трохи пізніше за фігуру — з розмиття й легкого
    /// зсуву, — а зникає швидко, щоб не мерехтіти, поки фігура стискається.
    static func notchContent(blur: CGFloat, offset: CGFloat, delay: Double) -> AnyTransition {
        if Style.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: NotchContentReveal(opacity: 0, blur: blur, offset: offset),
                identity: NotchContentReveal(opacity: 1, blur: 0, offset: 0)
            )
            .animation(.easeOut(duration: 0.28).delay(delay)),
            removal: .modifier(
                active: NotchContentReveal(opacity: 0, blur: blur * 0.6, offset: offset * 0.5),
                identity: NotchContentReveal(opacity: 1, blur: 0, offset: 0)
            )
            .animation(.easeIn(duration: 0.12))
        )
    }
}

private struct NotchContentReveal: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
            .offset(y: offset)
    }
}
