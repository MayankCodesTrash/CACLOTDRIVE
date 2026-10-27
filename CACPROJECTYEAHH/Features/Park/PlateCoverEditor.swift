import SwiftUI

/// Shown before a photo is sent to Google. The user draws boxes over license plates; those areas are
/// painted solid black on this phone first, so the plate never leaves it.
struct PlateCoverEditor: View {
    let photo: UIImage
    @Binding var boxes: [PlateBox]
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing: PlateBox?
    @State private var suggesting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                Spacer()
                Button("Undo") { if !boxes.isEmpty { boxes.removeLast() } }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.warmWhite).frame(minHeight: 44)
                    .disabled(boxes.isEmpty).opacity(boxes.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, Lot.Space.gutter).padding(.top, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cover license plates").font(.system(size: 28, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                Text("Drag on the photo to draw a box over any plate. Boxes turn solid black before the photo is sent. Drag a box to move it, pull its corner to resize, or tap ✕ to remove it.")
                    .font(LotType.caption).foregroundStyle(Lot.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Lot.Space.gutter).padding(.top, 8)

            canvas
                .padding(Lot.Space.gutter)

            VStack(spacing: 10) {
                Button {
                    suggesting = true
                    Task {
                        let found = await PlateBox.suggestions(in: photo)
                        boxes.append(contentsOf: found.filter { candidate in !boxes.contains { $0.overlaps(candidate) } })
                        suggesting = false
                    }
                } label: {
                    Label(suggesting ? "Looking for text…" : "Suggest boxes over text", systemImage: "text.viewfinder")
                }
                .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
                .disabled(suggesting)

                Button {
                    dismiss()
                    onSend()
                } label: {
                    Text(boxes.isEmpty ? "No plate in view, send" : "Cover \(boxes.count) and send")
                }
                .buttonStyle(LotButtonStyle(fullWidth: true))
            }
            .padding(.horizontal, Lot.Space.gutter).padding(.bottom, 16)
        }
        .lotScreen()
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fitted = Self.fit(photo.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: photo).resizable().frame(width: fitted.width, height: fitted.height)
                Color.clear
                    .frame(width: fitted.width, height: fitted.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { drawing = PlateBox(from: $0.startLocation, to: $0.location, in: fitted) }
                            .onEnded { value in
                                let box = PlateBox(from: value.startLocation, to: value.location, in: fitted)
                                if box.isUsable { boxes.append(box) }
                                drawing = nil
                            }
                    )
                ForEach(boxes) { box in
                    BoxOverlay(box: box, canvas: fitted) { updated in
                        if let i = boxes.firstIndex(where: { $0.id == box.id }) { boxes[i] = updated }
                    } onDelete: {
                        boxes.removeAll { $0.id == box.id }
                    }
                }
                if let drawing {
                    Rectangle().fill(.black.opacity(0.6))
                        .overlay(Rectangle().strokeBorder(Lot.lime, lineWidth: 2))
                        .frame(width: drawing.width * fitted.width, height: drawing.height * fitted.height)
                        .offset(x: drawing.x * fitted.width, y: drawing.y * fitted.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static func fit(_ size: CGSize, in container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private struct BoxOverlay: View {
        let box: PlateBox
        let canvas: CGSize
        let onChange: (PlateBox) -> Void
        let onDelete: () -> Void

        @State private var start: PlateBox?

        var body: some View {
            let w = box.width * canvas.width, h = box.height * canvas.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.black.opacity(0.85))
                    .overlay(Rectangle().strokeBorder(Lot.lime, lineWidth: 2))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = start ?? box
                                start = base
                                onChange(base.moved(dx: value.translation.width / canvas.width, dy: value.translation.height / canvas.height))
                            }
                            .onEnded { _ in start = nil }
                    )
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Lot.warmWhite, Lot.charcoal)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove box")
                .offset(x: -11, y: -11)
                Circle().fill(Lot.lime).frame(width: 16, height: 16)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .offset(x: w - 22, y: h - 22)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = start ?? box
                                start = base
                                onChange(base.resized(dw: value.translation.width / canvas.width, dh: value.translation.height / canvas.height))
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .offset(x: box.x * canvas.width, y: box.y * canvas.height)
        }
    }
}

extension PlateBox {
    /// True when more than half of the smaller box is covered by the other.
    nonisolated func overlaps(_ other: PlateBox) -> Bool {
        let a = CGRect(x: x, y: y, width: width, height: height)
        let b = CGRect(x: other.x, y: other.y, width: other.width, height: other.height)
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height > 0.5 * min(a.width * a.height, b.width * b.height)
    }
}
