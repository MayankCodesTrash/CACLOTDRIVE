import SwiftUI

/// "Check with AI" block used by the editor and the detail screen.
struct AIParkingSection: View {
    let photo: Data?
    @Binding var analysis: ParkingAnalysis?
    /// Called with the plate-covered photo. The caller must store it in place of the original, which is never kept.
    var onPhotoCovered: (Data) -> Void = { _ in }

    @State private var coordinator = ParkingAICoordinator()
    @State private var showOnboarding = false
    @State private var settings = AISettings.shared
    @State private var showPlateEditor = false
    @State private var plateBoxes: [PlateBox] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let analysis {
                AIFeedbackCard(analysis: analysis)
                HStack(spacing: 12) {
                    Button("Check again") { start() }
                        .buttonStyle(LotButtonStyle(kind: .ghost))
                        .disabled(coordinator.isBusy || photo == nil)
                    Button("Remove feedback") { self.analysis = nil }
                        .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(Lot.lime)
                        Text("Want a second opinion?").font(LotType.title).foregroundStyle(Lot.warmWhite)
                    }
                    Text("AI can look at your photo and describe how you parked: lines, centering and straightness. It gives tips, not scores.")
                        .font(LotType.caption).foregroundStyle(Lot.muted)
                    Button(action: start) {
                        Label(buttonTitle, systemImage: "sparkles")
                    }
                    .buttonStyle(LotButtonStyle(fullWidth: true))
                    .disabled(coordinator.isBusy || photo == nil)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Lot.charcoalRaised))
            }

            if case .failed(let message) = coordinator.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.85))
            }
            if coordinator.isBusy {
                HStack(spacing: 10) {
                    ProgressView().tint(Lot.warmWhite)
                    Text(coordinator.phase == .preparing ? "Covering plates, blurring faces and text…" : "Checking your parking…")
                        .font(LotType.caption).foregroundStyle(Lot.muted)
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            AIOnboardingSheet { start() }.presentationBackground(Lot.charcoal)
        }
        .sheet(isPresented: $showPlateEditor) {
            if let photo, let image = UIImage(data: photo) {
                PlateCoverEditor(photo: image, boxes: $plateBoxes) { send() }
                    .presentationBackground(Lot.charcoal)
            }
        }
        #if DEBUG
        .task {
            let args = CommandLine.arguments
            if args.contains("-showAIOnboarding") { try? await Task.sleep(for: .milliseconds(900)); showOnboarding = true }
            if args.contains("-showPlateEditor") { try? await Task.sleep(for: .milliseconds(900)); showPlateEditor = true }
            if args.contains("-fakeAnalysis") {
                analysis = ParkingAnalysis(
                    assessable: true, confidence: .medium,
                    summary: "The car sits inside the lines and looks a little closer to the left one.",
                    findings: [
                        .init(aspect: .inLines, status: .good, observation: "Both sides look inside the painted lines."),
                        .init(aspect: .centering, status: .okay, observation: "Slightly closer to the left line than the right."),
                        .init(aspect: .straightness, status: .unclear, observation: "The angle of the photo makes this hard to judge."),
                    ],
                    tips: ["Aim for the middle of the space as you pull in.", "Pause once the front wheels cross the line and check both sides."],
                    limitations: nil, model: "debug fixture", analyzedAt: .now)
            }
        }
        #endif
    }

    private var buttonTitle: String {
        coordinator.isBusy ? "Checking…" : "Check with AI"
    }

    private func start() {
        guard let photo else { return }
        guard settings.hasKey, settings.hasConsented else {
            showOnboarding = true
            return
        }
        // Always let the user cover plates first; the photo is only sent from the editor's button.
        showPlateEditor = true
    }

    private func send() {
        guard let photo else { return }
        var boxes = plateBoxes
        // Covered plates are permanent: the black version replaces the original right now, before anything is sent,
        // so the uncovered photo is never shown, saved or shared again even if the check fails.
        if !boxes.isEmpty, let image = UIImage(data: photo),
           let covered = PrivacyRedactor.cover(image, with: boxes).jpegData(compressionQuality: 0.92) {
            onPhotoCovered(covered)
            plateBoxes = []
            boxes = []
            Task {
                if let result = await coordinator.run(photo: covered, coverBoxes: []) { analysis = result }
            }
            return
        }
        Task {
            if let result = await coordinator.run(photo: photo, coverBoxes: boxes) { analysis = result }
        }
    }
}

/// One-time explanation and consent, plus API key entry if none is saved.
struct AIOnboardingSheet: View {
    let onReady: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AISettings.shared
    @State private var keyDraft = ""
    @State private var agreed = false

    private var canContinue: Bool { agreed && (settings.hasKey || !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, Lot.Space.gutter)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Before AI feedback").font(.system(size: 30, weight: .heavy)).foregroundStyle(Lot.warmWhite)

                    VStack(alignment: .leading, spacing: 14) {
                        point("icloud.and.arrow.up", "Your photo leaves your phone", "When you tap Check with AI, the photo is sent to Google's AI service. LOT never uploads anything else.")
                        point("eye.slash", "Plates are covered first", "You draw boxes over license plates and LOT paints them solid black on your phone. Faces and other text are also pixelated automatically, best effort.")
                        point("lock.shield", "Google's handling depends on your key", "How Google stores or uses the photo depends on the plan tied to the API key. Check Google's terms.")
                        point("person.2", "If you're under 18", "Ask a parent or guardian before using AI features.")
                        point("list.bullet.clipboard", "Tips, not scores", "The AI looks at one photo and gives tips. It doesn't measure anything and doesn't give a score.")
                    }

                    if !settings.hasKey {
                        VStack(alignment: .leading, spacing: 8) {
                            LotKicker(text: "Your AI API key")
                            SecureField("", text: $keyDraft, prompt: Text("Paste key from Google AI Studio").foregroundStyle(Lot.muted))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(Lot.warmWhite)
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
                            Text("Saved only in this phone's Keychain. A released app should call the AI service through its own server instead of holding a key.")
                                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                        }
                    }

                    Toggle(isOn: $agreed) {
                        Text("I understand my photo will be sent to Google.").font(LotType.caption).foregroundStyle(Lot.warmWhite)
                    }
                    .tint(Lot.lime)
                    .frame(minHeight: 44)
                }
                .padding(Lot.Space.gutter)
            }

            Button {
                if !settings.hasKey { settings.saveKey(keyDraft) }
                settings.setConsent(true)
                dismiss()
                onReady()
            } label: {
                Text("Agree and continue")
            }
            .buttonStyle(LotButtonStyle(fullWidth: true))
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.45)
            .padding(Lot.Space.gutter)
        }
        .lotScreen()
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Lot.warmWhite).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(LotType.body.weight(.semibold)).foregroundStyle(Lot.warmWhite)
                Text(detail).font(LotType.caption).foregroundStyle(Lot.muted)
            }
        }
    }
}
