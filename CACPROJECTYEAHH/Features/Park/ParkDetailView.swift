import SwiftUI
import SwiftData

struct ParkDetailView: View {
    let check: ParkingCheck

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var showRecap = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    if !check.tags.isEmpty {
                        FlowLayout { ForEach(check.tags) { LotChip(text: $0.title) } }
                    }
                    if !check.note.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            LotKicker(text: "Note")
                            Text(check.note).font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.92))
                        }
                    }
                    if check.photo != nil {
                        AIParkingSection(photo: check.photo, analysis: Binding(
                            get: { check.aiAnalysis },
                            set: { check.aiAnalysis = $0 }
                        ), onPhotoCovered: { check.photo = $0 })
                    }
                    if let car = check.car, !car.nickname.isEmpty {
                        Label(car.nickname, systemImage: "car.side").font(LotType.body).foregroundStyle(Lot.muted)
                    }
                    Button { showRecap = true } label: {
                        Label("Create Recap", systemImage: "sparkles")
                    }
                    .buttonStyle(LotButtonStyle(fullWidth: true))
                }
                .padding(.horizontal, Lot.Space.gutter)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .clearsTabBar()
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .lotScreen()
        .sheet(isPresented: $editing) { ParkCheckEditor(check: check).presentationBackground(Lot.charcoal) }
        .sheet(isPresented: $showRecap) { ParkingRecapSheet(check: check).presentationBackground(Lot.charcoal) }
        .confirmationDialog("Delete this parking check?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(check)
                dismiss()
            }
        }
    }

    private var hero: some View {
        Color.clear
            .frame(height: 420)
            .overlay { ParkingImage(photo: check.photo) }
            .overlay {
                LinearGradient(stops: [
                    .init(color: Lot.charcoal.opacity(0.6), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: Lot.charcoal, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                HStack {
                    LotCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                    Menu {
                        Button("Edit", systemImage: "pencil") { editing = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Lot.warmWhite)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Lot.charcoal.opacity(0.55)))
                    }
                    .accessibilityLabel("More")
                }
                .padding(.horizontal, Lot.Space.gutter)
                .padding(.top, 58)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if check.isDemo { DemoBadge() }
                        if check.tries > 0 { LotChip(text: check.tries == 1 ? "1 try" : check.tries == 4 ? "4+ tries" : "\(check.tries) tries") }
                    }
                    Text(check.maneuver.title + " parking")
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                    Text(check.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        .font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.85))
                }
                .padding(Lot.Space.gutter)
                .allowsHitTesting(false)
            }
    }
}
