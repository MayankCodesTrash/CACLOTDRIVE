import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var drives: [Drive]

    private var sampleOn: Binding<Bool> {
        Binding(
            get: { drives.contains(where: \.isDemo) },
            set: { on in
                withAnimation {
                    if on { SampleData.load(into: context) } else { SampleData.clear(from: context) }
                }
            }
        )
    }

    @Environment(TripDetectionService.self) private var detection
    @Environment(\.openURL) private var openURL
    @State private var showSimulator = false
    @State private var ai = AISettings.shared
    @State private var web = WebImageSettings.shared
    @State private var webKeyDraft = ""
    @State private var keyDraft = ""
    @State private var modelDraft = AISettings.shared.model
    @State private var aiTestResult: (ok: Bool, message: String)?
    @State private var aiTesting = false

    private var detectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic drive detection").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Toggle(isOn: Binding(
                get: { detection.isEnabled },
                set: { on in Task { await detection.setEnabled(on) } }
            )) {
                Text("Detect drives while LOT is open").font(LotType.body).foregroundStyle(Lot.warmWhite)
            }
            .tint(Lot.lime)
            .frame(minHeight: 44)

            permissionRow("Motion & Fitness", detection.motionAuth)
            permissionRow("Location", detection.locationAuth)

            if detection.locationAuth == .denied || detection.motionAuth == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(LotButtonStyle(kind: .ghost))
            }

            Text("LOT only detects drives while it's open on your phone. It doesn't record in the background yet, uses battery while detecting, and keeps everything on this phone. Detection needs a real iPhone, since the simulator has no motion sensors. It can't tell whether you were driving or riding, so you can mark any trip as a passenger trip.")
                .font(LotType.caption).foregroundStyle(Lot.muted)
            if detection.usesLocationOnly && detection.isEnabled {
                Text("Motion & Fitness isn't available, so LOT is using location only and waits for stronger evidence before recording.")
                    .font(LotType.caption).foregroundStyle(Lot.muted)
            }
        }
    }

    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Garage pictures").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Toggle(isOn: Binding(get: { VehicleImageStore.shared.findsImagesOnline }, set: { VehicleImageStore.shared.findsImagesOnline = $0 })) {
                Text("Find my car's photo online").font(LotType.body).foregroundStyle(Lot.warmWhite)
            }
            .tint(Lot.lime)
            .frame(minHeight: 44)
            Text("When on, LOT sends only your car's year, make, model and trim to Wikimedia Commons to find a photo, and removes the background on your phone. Off, or offline, LOT shows a bundled illustration. Photos keep their authors' credit.")
                .font(LotType.caption).foregroundStyle(Lot.muted)
            webSearchBlock
            Button("Clear saved car pictures") { VehicleImageCache().clearAll(); VehicleImageStore.shared.cache.clearAll() }
                .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)
        }
    }

    private var webSearchBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Web photo search").font(LotType.body.weight(.semibold)).foregroundStyle(Lot.warmWhite).padding(.top, 8)
            Toggle(isOn: Binding(get: { web.isEnabled }, set: { web.setEnabled($0) })) {
                Text("Search the web for real photos").font(LotType.body).foregroundStyle(Lot.warmWhite)
            }
            .tint(Lot.lime)
            .frame(minHeight: 44)

            HStack {
                Text("Search key").font(LotType.body).foregroundStyle(Lot.warmWhite)
                Spacer()
                Text(web.hasKey ? "Saved" : "Not added").font(LotType.caption).foregroundStyle(web.hasKey ? Lot.lime : Lot.muted)
            }
            .frame(minHeight: 36)

            SecureField("", text: $webKeyDraft, prompt: Text(web.hasKey ? "Replace key" : "Paste your Brave Search API key").foregroundStyle(Lot.muted))
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Lot.warmWhite)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
            HStack(spacing: 12) {
                Button("Save key") { web.saveKey(webKeyDraft); webKeyDraft = "" }
                    .buttonStyle(LotButtonStyle(kind: .ghost))
                    .disabled(webKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if web.hasKey {
                    Button("Remove key") { web.removeKey() }
                        .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)
                }
            }
            Text("With a key, LOT searches the web (through Brave's Image Search API) for a real photo of your car, using only its year, make, model, trim and color, then removes the background on your phone. Wikimedia Commons and bundled illustrations are the backup. The service is paid per search, so each car is looked up once and saved. Web photos belong to their owners, so they stay in your own Garage and aren't included when you share. The key is kept in this phone's Keychain. A released app should search through your own server.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking AI").font(LotType.title).foregroundStyle(Lot.warmWhite)
            HStack {
                Text("API key").font(LotType.body).foregroundStyle(Lot.warmWhite)
                Spacer()
                Text(ai.hasKey ? "Saved" : "Not added").font(LotType.caption).foregroundStyle(ai.hasKey ? Lot.lime : Lot.muted)
            }
            .frame(minHeight: 36)

            SecureField("", text: $keyDraft, prompt: Text(ai.hasKey ? "Replace key" : "Paste your AI API key").foregroundStyle(Lot.muted))
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Lot.warmWhite)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))

            HStack(spacing: 12) {
                Button("Save key") {
                    if ai.saveKey(keyDraft) {
                        keyDraft = ""
                        aiTestResult = (true, "Key saved on this phone. Tap Test AI connection to check it.")
                    } else {
                        aiTestResult = (false, "The key couldn't be saved to this phone's Keychain. Try again.")
                    }
                }
                    .buttonStyle(LotButtonStyle(kind: .ghost))
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if ai.hasKey {
                    Button("Remove key") { ai.removeKey() }
                        .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)
                }
            }

            TextField("", text: $modelDraft, prompt: Text(AISettings.defaultModel).foregroundStyle(Lot.muted))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Lot.warmWhite)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
                .onSubmit { ai.setModel(modelDraft) }
            Text("Model name. Google renames models over time, so change it here if requests start failing.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)

            Button {
                ai.setModel(modelDraft)
                aiTesting = true
                aiTestResult = nil
                Task {
                    let analyzer = GeminiParkingAnalyzer(apiKey: ai.apiKey, model: ai.model)
                    do {
                        try await analyzer.testConnection()
                        aiTestResult = (true, "Google accepted the key and knows the model \"\(ai.model)\". No photo was sent.")
                    } catch {
                        aiTestResult = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                    aiTesting = false
                }
            } label: {
                Label(aiTesting ? "Testing…" : "Test AI connection", systemImage: "bolt.horizontal")
            }
            .buttonStyle(LotButtonStyle(kind: .ghost))
            .disabled(aiTesting || !ai.hasKey)
            if let aiTestResult {
                Label(aiTestResult.message, systemImage: aiTestResult.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(LotType.caption).foregroundStyle(aiTestResult.ok ? Lot.lime : Lot.warmWhite.opacity(0.85))
            }

            Toggle(isOn: Binding(get: { ai.hasConsented }, set: { ai.setConsent($0) })) {
                Text("I agree to send parking photos to Google when I ask for AI feedback").font(LotType.caption).foregroundStyle(Lot.warmWhite)
            }
            .tint(Lot.lime)
            .frame(minHeight: 44)

            Text("Only photos you choose to check are sent, after you cover license plates and faces and text are pixelated on this phone (best effort). The key is stored in this phone's Keychain. For a real release, route requests through your own server so no key ships inside the app.")
                .font(LotType.caption).foregroundStyle(Lot.muted)
        }
    }

    private func permissionRow(_ name: String, _ auth: SensorAuthorization) -> some View {
        HStack {
            Text(name).font(LotType.body).foregroundStyle(Lot.warmWhite)
            Spacer()
            Text(label(for: auth)).font(LotType.caption).foregroundStyle(auth == .authorized ? Lot.lime : Lot.muted)
        }
        .frame(minHeight: 36)
    }

    private func label(for auth: SensorAuthorization) -> String {
        switch auth {
        case .authorized: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .unavailable: "Unavailable"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                Spacer()
                Button("Done") { dismiss() }
                    .font(LotType.caption.weight(.semibold)).foregroundStyle(Lot.lime).frame(minHeight: 44)
            }
            .padding(Lot.Space.gutter)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    detectionSection

                    garageSection

                    aiSection


                    section("Sample data") {
                        Toggle(isOn: sampleOn) {
                            Text("Show sample drives").font(LotType.body).foregroundStyle(Lot.warmWhite)
                        }
                        .tint(Lot.lime)
                        .frame(minHeight: 44)
                        Text("Fictional trips and parking checks for demos. They're labeled Sample everywhere and removed when you turn this off. Your own entries are never touched. Sample routes follow real streets, with route geometry from OpenStreetMap (© OpenStreetMap contributors).")
                    }

                    section("Developer · simulate a drive") {
                        Button {
                            showSimulator = true
                        } label: {
                            Label(detection.isSimulating ? "Simulating…" : "Simulate a drive…", systemImage: "play.fill")
                        }
                        .buttonStyle(LotButtonStyle(kind: .ghost))
                        .disabled(detection.isSimulating)
                        Text("Pick a start and an end. LOT replays scripted sensor data along real roads through the real detection logic. The trip is saved as simulated, then LOT asks whether you were driving and offers a parking photo, just like a real drive.")
                    }

                    section("Appearance") {
                        Toggle(isOn: Binding(get: { SampleLabels.isVisible }, set: { UserDefaults.standard.set($0, forKey: SampleLabels.key) })) {
                            Text("Label sample data").font(LotType.body).foregroundStyle(Lot.warmWhite)
                        }
                        .tint(Lot.lime)
                        .frame(minHeight: 44)
                        Text("Off hides the \"Sample\" tags, which is handy for screenshots and video. Sample items can still be removed above.")
                    }

                    section("Privacy & safety") {
                        Text("Everything in LOT is stored on this phone and private by default. Nothing is shared unless you tap Share, or ask for AI parking feedback, which sends that one photo to Google. LOT never needs input while you drive, so add photos and notes after you park.")
                    }
                }
                .padding(.horizontal, Lot.Space.gutter)
            }
        }
        .lotScreen()
        .sheet(isPresented: $showSimulator) {
            SimulateDriveSheet { trip in
                dismiss()
                Task { await detection.simulateDrive(trip) }
            }
            .presentationBackground(Lot.charcoal)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(LotType.title).foregroundStyle(Lot.warmWhite)
            content().font(LotType.caption).foregroundStyle(Lot.muted)
        }
    }
}
