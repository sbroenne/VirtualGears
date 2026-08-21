import SwiftUI
import VirtualGearsCore

/// First run asks only for the two physical facts virtual shifting cannot
/// infer: what is on the bike and where the chain is left. Simulated gearing
/// starts on Standard 24 and can be changed independently in Settings later.
struct SetupWizardView: View {
    @Bindable var store: ConfigurationStore
    var onFinish: () -> Void

    @State private var step: WizardStep = .bike
    @State private var chainringTeeth: [Int]
    @State private var cogTeeth: [Int]
    @State private var cassetteCogs: [Int]

    private enum WizardStep {
        case bike, parkedGear
    }

    init(store: ConfigurationStore, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        let physical = store.configuration.physical
        _chainringTeeth = State(initialValue: physical.chainringTeeth)
        _cogTeeth = State(initialValue: physical.cogTeeth)
        _cassetteCogs = State(
            initialValue: physical.isSingleSprocket
                ? store.configuration.cassette.cogs : physical.cogTeeth
        )
    }

    var body: some View {
        Group {
            switch step {
            case .bike:
                WizardBikeSetupStep(
                    store: store,
                    chainringTeeth: $chainringTeeth,
                    cogTeeth: $cogTeeth,
                    cassetteCogs: $cassetteCogs,
                    onUseBike: useBike
                )
            case .parkedGear:
                WizardParkedGearStep(store: store, onFinish: finish)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if step == .parkedGear {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { step = .bike }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func useBike() {
        store.configureFirstRunBike(
            chainringTeeth: chainringTeeth,
            cogTeeth: cogTeeth
        )
        step = .parkedGear
    }

    private func finish() {
        guard store.completeSetupWizard() else { return }
        onFinish()
    }
}

private struct WizardBikeSetupStep: View {
    @Bindable var store: ConfigurationStore
    @Binding var chainringTeeth: [Int]
    @Binding var cogTeeth: [Int]
    @Binding var cassetteCogs: [Int]
    let onUseBike: () -> Void

    var body: some View {
        Form {
            Section {
                Text(
                    "Tell us what is physically on the bike attached to the "
                        + "trainer. Virtual Gears uses this only to calculate "
                        + "the quiet, safe gear to leave the chain in."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                LabeledContent("Virtual gears", value: "Standard 24")
                Text("Choose other virtual gears later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Your bike")
            }

            Section {
                ChoiceRow(
                    title: "Cassette",
                    selected: !isSingleSprocket
                ) {
                    cogTeeth = cassetteCogs
                }
                .accessibilityIdentifier("wizard.rear.cassette")

                ChoiceRow(
                    title: "Zwift Cog or another single sprocket",
                    note: "A Zwift Cog is normally 14T.",
                    selected: isSingleSprocket
                ) {
                    if !isSingleSprocket {
                        cogTeeth = PhysicalSetup.zwiftCogTeeth
                    }
                }
                .accessibilityIdentifier("wizard.rear.singleSprocket")

                if isSingleSprocket {
                    Stepper(value: sprocketTeeth, in: 9...30) {
                        LabeledContent("Sprocket", value: "\(cogTeeth[0])T")
                    }
                    .accessibilityIdentifier("wizard.sprocketTeeth")
                }
            } header: {
                Text("Back of the bike")
            }

            Section {
                NavigationLink {
                    PhysicalChainringView(teeth: $chainringTeeth)
                } label: {
                    LabeledContent(
                        "Chainrings",
                        value: chainringTeeth.map(String.init).joined(separator: "/")
                    )
                }

                if !isSingleSprocket {
                    NavigationLink {
                        PhysicalCassetteView(cogs: cassetteBinding)
                    } label: {
                        LabeledContent("Cassette", value: cassetteSummary)
                    }
                }
            } header: {
                Text("Physical parts")
            }
        }
        .accessibilityIdentifier("screen.setupWizard")
        .navigationTitle("Set up Virtual Gears")
        .safeAreaInset(edge: .bottom) {
            Button("Use this bike setup", action: onUseBike)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding()
                .accessibilityIdentifier("wizard.useBikeSetup")
        }
    }

    private var isSingleSprocket: Bool {
        cogTeeth.count == 1
    }

    private var cassetteSummary: String {
        guard let smallest = cogTeeth.first, let largest = cogTeeth.last else {
            return "—"
        }
        return "\(cogTeeth.count)-speed · \(smallest)-\(largest)"
    }

    private var cassetteBinding: Binding<[Int]> {
        Binding(
            get: { cogTeeth },
            set: {
                cassetteCogs = $0
                cogTeeth = $0
            }
        )
    }

    private var sprocketTeeth: Binding<Int> {
        Binding(
            get: { cogTeeth.first ?? PhysicalSetup.zwiftCogTeeth[0] },
            set: { cogTeeth = [$0] }
        )
    }
}

private struct WizardParkedGearStep: View {
    @Bindable var store: ConfigurationStore
    let onFinish: () -> Void

    var body: some View {
        Form {
            Section {
                Text(
                    "Virtual Gears changes resistance from one fixed physical "
                        + "gear. Move the chain once, then leave it there for "
                        + "the whole ride."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } header: {
                Text("Before you ride")
            }

            Section {
                Text(store.configuration.parkedGearAdviceText)

                if let warning = store.configuration.parkedGearWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Recommended")
            }

            Section {
                ForEach(candidates, id: \.self) { gear in
                    ChoiceRow(
                        title: gear.name,
                        note: caption(for: gear),
                        noteColor: isWorkable(gear) ? nil : .orange,
                        selected: gear == store.configuration.parkedGear
                    ) {
                        store.park(in: gear)
                    }
                }
            } header: {
                Text("Position your chain")
            }
        }
        .accessibilityIdentifier("screen.setupWizard")
        .navigationTitle("Position your chain")
        .safeAreaInset(edge: .bottom) {
            Button("Finish setup", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .disabled(
                    !store.configuration.hasSafeGearing
                        || store.configuration.parkedGear == nil
                        || store.configuration.parkedGearPutsGearsOutOfReach
                )
                .padding()
        }
        .onAppear {
            if store.configuration.parkedGear == nil {
                store.parkInSuggestion()
            }
        }
    }

    private func caption(for gear: ParkedGear) -> String? {
        if gear == store.configuration.suggestedParkedGear {
            return "Recommended — quietest that works"
        } else if !isWorkable(gear) {
            return "Puts some gears out of reach"
        }
        return nil
    }

    private var candidates: [ParkedGear] {
        let suggestion = store.configuration.suggestedParkedGear
        return ParkedGearAdvice.usableParkedGears(
            in: store.configuration.physical
        ).sorted { left, right in
            if left == right { return false }
            if left == suggestion { return true }
            if right == suggestion { return false }
            let leftWorks = isWorkable(left)
            let rightWorks = isWorkable(right)
            if leftWorks != rightWorks { return leftWorks }
            return left.ratio < right.ratio
        }
    }

    private func isWorkable(_ gear: ParkedGear) -> Bool {
        guard let drivetrain = store.configuration.drivetrain else { return true }
        return ParkedGearAdvice.isWorkable(gear, simulating: drivetrain)
    }
}
