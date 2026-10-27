import SwiftUI

/// Custom floating tab bar. Tap a tab, or press and slide a finger along the bar: the lime pill follows it.
struct LotTabBar: View {
    @Binding var selection: LotTab
    @Namespace private var pill
    @State private var barWidth: CGFloat = 0

    private let inset: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LotTab.allCases) { tab in cell(tab) }
        }
        .padding(inset)
        .frame(maxWidth: 360)
        .background(GeometryReader { geo in Color.clear.onAppear { barWidth = geo.size.width }.onChange(of: geo.size.width) { _, new in barWidth = new } })
        .background(
            Capsule()
                .fill(Lot.charcoalRaised)
                .overlay(Capsule().strokeBorder(Lot.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        )
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let tab = Self.tab(atX: value.location.x - inset, barWidth: barWidth - inset * 2), tab != selection else { return }
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { selection = tab }
                }
        )
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.bottom, 6)
    }

    /// Which tab sits under a finger at `x`, with the bar split into equal zones. Positions past the ends count as the end tabs.
    static func tab(atX x: CGFloat, barWidth: CGFloat) -> LotTab? {
        guard barWidth > 0 else { return nil }
        let tabs = LotTab.allCases
        let index = Int((x / barWidth * CGFloat(tabs.count)).rounded(.down))
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    private func cell(_ tab: LotTab) -> some View {
        let selected = selection == tab
        return VStack(spacing: 3) {
            Image(systemName: tab.symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(height: 22)
            Text(tab.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? Lot.charcoal : Lot.warmWhite.opacity(0.62))
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if selected {
                Capsule().fill(Lot.lime).matchedGeometryEffect(id: "pill", in: pill)
            }
        }
        // The container's drag gesture handles touches, so VoiceOver gets its own action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { selection = tab } }
    }
}
