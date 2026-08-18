import SwiftUI
import VirtualGearsCore

/// The setup guide walks a rider through the three facts Virtual Gears needs
/// before it can shift honestly, in the order they actually depend on each
/// other: what gearing is on the bike, where the chain is parked, and what
/// wheel size to assume. Doing this as one guided flow — instead of three
/// separate rows scattered through Settings — means the second and third
/// answers can be *computed* from the first, rather than asked as three
/// unrelated questions.
///
/// Picking a named groupset here answers two questions at once: it is both
/// what is physically bolted to the bike (so the chain-position advice is
/// right) and the gearing that gets simulated (so the ladder matches a bike
/// the rider already recognises), because for almost everyone those are the
/// same bike. A rider who wants different gearing simulated than what is
/// on the bike — running a single Zwift Cog and simulating a twelve-speed,
/// say — can still split the two apart afterwards in Settings; the guide
/// just does not ask that as a separate question up front.
struct SetupWizardView: View {
    @Bindable var store: ConfigurationStore
    var onFinish: () -> Void

    @State private var step: WizardStep = .groupset

    enum WizardStep: Int {
        case groupset, parkedGear, wheelSize
    }

    var body: some View {
        Group {
            switch step {
            case .groupset:
                WizardGroupsetStep(store: store, onNext: { advance() })
            case .parkedGear:
                WizardParkedGearStep(store: store, onNext: { advance() })
            case .wheelSize:
                WizardWheelSizeStep(store: store, onFinish: finish)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if step == .groupset {
                    Button("Skip") { finish() }
                } else {
                    Button("Back") { back() }
                }
            }
        }
        .accessibilityIdentifier("screen.setupWizard")
        .onDisappear {
            // Covers a swipe-to-dismiss as well as Skip/Done: either way the
            // guide has been seen and should not reopen on its own.
            store.completeSetupWizard()
        }
    }

    private func advance() {
        switch step {
        case .groupset: step = .parkedGear
        case .parkedGear: step = .wheelSize
        case .wheelSize: finish()
        }
    }

    private func back() {
        switch step {
        case .groupset: break
        case .parkedGear: step = .groupset
        case .wheelSize: step = .parkedGear
        }
    }

    private func finish() {
        store.completeSetupWizard()
        onFinish()
    }
}

/// Step 1. One choice — the groupset — sets what is on the bike and what is
/// simulated together, which is why this is a single list rather than the
/// separate "physical parts" and "gearing to simulate" screens Settings has.
/// Selecting a row applies it immediately and moves on, matching the rest of
/// the app's "choosing is the action" pattern.
private struct WizardGroupsetStep: View {
    @Bindable var store: ConfigurationStore
    let onNext: () -> Void

    var body: some View {
        Form {
            Section {
                Text(
                    "Pick the groupset on your bike. This sets both what the "
                        + "bike is parked in and the gearing Virtual Gears "
                        + "simulates."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            ForEach(GroupsetBrand.allCases) { brand in
                Section {
                    ForEach(GroupsetCatalog.groupsets(brand: brand)) { set in
                        ChoiceRow(
                            title: set.name,
                            spokenTitle: set.qualifiedName,
                            note: "\(set.speeds)-speed · \(set.note)",
                            selected: set.id == store.configuration.groupset?.id
                        ) {
                            store.adoptGroupsetForBikeAndGears(set)
                            onNext()
                        }
                    }
                } header: {
                    Text(brand.name)
                }
            }
            Section {
                Button("Single sprocket, or my bike isn't listed") {
                    onNext()
                }
            } footer: {
                Text(
                    "You can set up a single sprocket, a virtual ladder, or "
                        + "your own chainrings and cassette afterwards in "
                        + "Settings."
                )
            }
        }
        .navigationTitle("Your groupset")
    }
}

/// Step 2. The recommendation is computed from whatever was just chosen (or
/// left as-is, if the rider skipped step 1), pre-selected so confirming it is
/// a single tap — the same "recommend, then let them confirm" idea from the
/// parked-gear screen in Settings, reused here so the guide asks it too.
private struct WizardParkedGearStep: View {
    @Bindable var store: ConfigurationStore
    let onNext: () -> Void

    var body: some View {
        Form {
            Section {
                Text(store.configuration.parkedGearAdviceText)

                if let warning = store.configuration.parkedGearWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Where's the chain?")
            } footer: {
                Text(
                    "Virtual Gears changes gear by changing the wheel size "
                        + "the trainer works from, so it has to know the gear "
                        + "it is working from. Park the chain once and leave "
                        + "it there."
                )
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
                Text("Which gear is it in")
            }
        }
        .navigationTitle("Gear the bike is in")
        .safeAreaInset(edge: .bottom) {
            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.configuration.parkedGear == nil)
                .padding()
                .background(.bar)
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
        ParkedGearAdvice.usableParkedGears(in: store.configuration.physical)
    }

    private func isWorkable(_ gear: ParkedGear) -> Bool {
        guard let drivetrain = store.configuration.drivetrain else { return true }
        return ParkedGearAdvice.isWorkable(gear, simulating: drivetrain)
    }
}

/// Step 3. The last fact the guide needs: the wheel size to assume when a
/// riding app does not send its own. Kept to a single Stepper — the guide is
/// meant to be quick, and the full text-entry option stays in Settings for
/// anyone who wants an exact, typed value.
private struct WizardWheelSizeStep: View {
    @Bindable var store: ConfigurationStore
    let onFinish: () -> Void

    var body: some View {
        Form {
            Section {
                Stepper(
                    value: wheelSize,
                    in: lowerBound...upperBound,
                    step: 1
                ) {
                    LabeledContent(
                        "Wheel circumference",
                        value: "\(store.configuration.neutralCircumferenceMillimeters) mm"
                    )
                }
            } header: {
                Text("Normal wheel size")
            } footer: {
                Text(
                    "Used only when your riding app does not send its own "
                        + "wheel circumference. Virtual Gears uses 2070 mm by "
                        + "default, and this can be changed later in Settings."
                )
            }
        }
        .navigationTitle("Wheel size")
        .safeAreaInset(edge: .bottom) {
            Button("Done") { onFinish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding()
                .background(.bar)
        }
    }

    private var wheelSize: Binding<Int> {
        Binding(
            get: { store.configuration.neutralCircumferenceMillimeters },
            set: { store.setNormalWheelCircumference(millimeters: $0) }
        )
    }

    private var lowerBound: Int {
        Int(TrainerSafety.supportedRidingAppCircumferenceMillimeters.lowerBound)
    }

    private var upperBound: Int {
        Int(TrainerSafety.supportedRidingAppCircumferenceMillimeters.upperBound)
    }
}
