import SwiftUI

struct HydrationSettingView: View {
    @State private var dailyGoal = 2000
    @State private var defaultAmount = 250
    @State private var reminderInterval = 60

    @State private var isEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Hydration Tracking", isOn: $isEnabled)
            } footer: {
                Text("Track your daily water intake and receive reminders.")
            }

            if isEnabled {
                Section {
                    Stepper(value: $dailyGoal, in: 500...5000, step: 100) {
                        LabeledContent("Daily Goal", value: "\(dailyGoal) mL")
                    }

                    Stepper(value: $defaultAmount, in: 50...1000, step: 50) {
                        LabeledContent("Default Intake", value: "\(defaultAmount) mL")
                    }
                } header: {
                    Text("Intake Goals")
                }
                Section {
                    Stepper(value: $reminderInterval, in: 15...240, step: 15) {
                        LabeledContent("Reminder Every", value: "\(reminderInterval) min")
                    }
                } header: {
                    Text("Notifications")
                }
                Section {
                    Label("Read Status", systemImage: "drop")
                    Label("Log Water Intake", systemImage: "drop.fill")
                    Label("View History", systemImage: "clock.arrow.circlepath")
                    Label("Set Daily Goal", systemImage: "target")
                } header: {
                    Text("Available Tools")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hydration")
        .animation(.default, value: isEnabled)
    }
}

#Preview {
    HydrationSettingView()
        .frame(width: 450)
}
