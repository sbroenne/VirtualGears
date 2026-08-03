import SwiftUI

struct SetupView: View {
    @Bindable var store: ConfigurationStore
    var isEditing = false
    var onFinish: (() -> Void)?

    private let exampleKickrUUID = "D2A00B65-7C4A-4F0A-A661-B3E378CA92B4"
    private let exampleClickUUID = "7E0C0A35-21E6-4B16-B90A-B509B8AC6DC3"

    var body: some View {
        Form {
            introduction
            kickrSection
            clickSection
            drivetrainSection
            circumferenceSection
            nextSection
        }
        .navigationTitle(isEditing ? "Settings" : "Set Up VirtualShift")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            finishButton
        }
        .interactiveDismissDisabled(isEditing && !store.configuration.canFinishSetup)
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "bicycle.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(isEditing ? "Ride setup" : "Let’s prepare your ride")
                    .font(.title2.bold())
                Text(
                    "Choose saved placeholders now. Hardware scanning and real "
                        + "Bluetooth connection status come next."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var kickrSection: some View {
        Section {
            Button {
                store.configuration.kickrName = "Wahoo KICKR"
                store.configuration.kickrUUID = exampleKickrUUID
            } label: {
                HStack {
                    Label("Use example KICKR", systemImage: "plus.circle")
                    Spacer()
                    Text("Placeholder")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 60)
            }

            TextField("Display name", text: kickrName)
                .textContentType(.name)
            TextField("Bluetooth UUID", text: kickrUUID)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if !store.configuration.kickrUUID.isEmpty,
               UUID(uuidString: store.configuration.kickrUUID) == nil {
                Label("Enter a valid UUID.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("KICKR trainer")
        } footer: {
            Text("Required. This saves an identity only; no trainer is connected.")
        }
    }

    private var clickSection: some View {
        Section {
            Toggle("Configure a Zwift Click", isOn: usesClick)
                .frame(minHeight: 60)

            if store.configuration.usesClick {
                Button {
                    store.configuration.clickName = "Zwift Click"
                    store.configuration.clickUUID = exampleClickUUID
                } label: {
                    Label("Use example Click", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                }
                TextField("Display name", text: clickName)
                TextField("Bluetooth UUID", text: clickUUID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                if !store.configuration.clickUUID.isEmpty,
                   UUID(uuidString: store.configuration.clickUUID) == nil {
                    Label("Enter a valid UUID.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Shift controller")
        } footer: {
            Text("Optional. Placeholder selection does not connect to hardware.")
        }
    }

    private var drivetrainSection: some View {
        Section("Drivetrain") {
            Picker("Preset", selection: drivetrainPreset) {
                ForEach(DrivetrainPreset.allCases) { preset in
                    VStack(alignment: .leading) {
                        Text(preset.name)
                        Text(preset.detail)
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.inline)

            Text(
                "\(store.configuration.drivetrainPreset.drivetrain.gears.count) "
                    + "allowed gear combinations; extreme cross-chaining is excluded."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var circumferenceSection: some View {
        Section {
            TextField("Millimeters", value: circumference, format: .number)
                .keyboardType(.numberPad)
                .accessibilityLabel("Neutral wheel circumference in millimeters")

            if store.configuration.isCircumferenceConfirmed {
                Label(
                    "\(store.configuration.neutralCircumferenceMillimeters) mm confirmed",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .accessibilityLabel(
                    "Neutral circumference confirmed at "
                        + "\(store.configuration.neutralCircumferenceMillimeters) millimeters"
                )
            } else if !store.configuration.hasSafeCircumference {
                Label(
                    "This value is unsafe for the selected drivetrain.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            } else {
                Button {
                    store.confirmCircumference()
                } label: {
                    Text(
                        "Confirm \(store.configuration.neutralCircumferenceMillimeters) mm"
                    )
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Neutral circumference")
        } footer: {
            Text(
                "Default: 2070 mm. Confirm this once before continuing. "
                    + "Changing it requires confirmation again."
            )
        }
    }

    private var nextSection: some View {
        Section {
            Label("Next: Bluetooth scanning", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            Text(
                "The next product milestone will discover and connect your saved hardware. "
                    + "VirtualShift does not claim a connection today."
            )
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var finishButton: some View {
        Button {
            store.finishSetup()
            onFinish?()
        } label: {
            Text(isEditing ? "Save Setup" : "Finish Setup")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.configuration.canFinishSetup)
        .padding()
        .background(.bar)
        .accessibilityHint(
            store.configuration.canFinishSetup
                ? "Saves setup and shows the ready screen"
                : "Complete the required fields and confirm circumference first"
        )
    }

    private var kickrName: Binding<String> {
        persistedBinding(\.kickrName)
    }

    private var kickrUUID: Binding<String> {
        persistedBinding(\.kickrUUID)
    }

    private var usesClick: Binding<Bool> {
        persistedBinding(\.usesClick)
    }

    private var clickName: Binding<String> {
        persistedBinding(\.clickName)
    }

    private var clickUUID: Binding<String> {
        persistedBinding(\.clickUUID)
    }

    private var drivetrainPreset: Binding<DrivetrainPreset> {
        persistedBinding(\.drivetrainPreset)
    }

    private var circumference: Binding<Int> {
        Binding {
            store.configuration.neutralCircumferenceMillimeters
        } set: {
            store.setCircumference($0)
        }
    }

    private func persistedBinding<Value>(
        _ keyPath: WritableKeyPath<AppConfiguration, Value>
    ) -> Binding<Value> {
        Binding {
            store.configuration[keyPath: keyPath]
        } set: {
            store.configuration[keyPath: keyPath] = $0
        }
    }
}

#Preview("Setup") {
    NavigationStack {
        SetupView(
            store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.setup")!)
        )
    }
}
