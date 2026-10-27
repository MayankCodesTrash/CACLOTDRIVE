import SwiftUI

struct LotButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost }
    var kind: Kind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LotType.button)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(kind == .primary ? Lot.charcoal : Lot.warmWhite)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(Capsule().fill(kind == .primary ? Lot.lime : Lot.warmWhite.opacity(0.08)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}


struct LotChip: View {
    let text: String
    var filled = false
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text)
        }
        .font(LotType.labelSmall)
        .foregroundStyle(filled ? Lot.charcoal : Lot.warmWhite)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(filled ? Lot.lime : Lot.warmWhite.opacity(0.12)))
    }
}

/// Marks fictional content so it is never confused with something the user recorded. Hidden when the user turns sample labels off.
struct DemoBadge: View {
    @AppStorage(SampleLabels.key) private var visible = false

    var body: some View {
        if visible {
            Text("Sample")
                .font(LotType.labelSmall)
                .foregroundStyle(Lot.warmWhite.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Lot.warmWhite.opacity(0.14)))
                .accessibilityLabel("Sample data")
        }
    }
}

struct LotKicker: View {
    let text: String
    var body: some View {
        Text(text)
            .font(LotType.label)
            .foregroundStyle(Lot.muted)
    }
}

struct LotEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Lot.warmWhite.opacity(0.8))
            Text(title).font(LotType.headline).foregroundStyle(Lot.warmWhite)
            Text(message)
                .font(LotType.caption)
                .foregroundStyle(Lot.muted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(LotButtonStyle())
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Shared screen header: optional kicker, big title, optional trailing control.
struct LotHeader<Trailing: View>: View {
    var kicker: String?
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let kicker { LotKicker(text: kicker) }
                Text(title).font(LotType.display).foregroundStyle(Lot.warmWhite)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, Lot.Space.gutter)
    }
}

/// Five dots showing a 1-5 self-rating.
struct ConfidenceDots: View {
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= value ? Lot.warmWhite : Lot.warmWhite.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(value > 0 ? "Confidence \(value) of 5" : "No confidence rating")
    }
}

/// Selectable chip. Selection is warm white, so lime stays reserved for primary actions.
struct LotToggleChip: View {
    let text: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(text).font(LotType.caption.weight(.medium))
            }
            .foregroundStyle(isOn ? Lot.charcoal : Lot.warmWhite)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(isOn ? Lot.warmWhite : Lot.warmWhite.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Round icon button used over imagery.
struct LotCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Lot.warmWhite)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Lot.charcoal.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
