import SwiftUI

struct HydrationSettingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .hydration) {
                Form {
                    Section {
                        ServiceToggleView(config: config)
                    } header: {
                        Text("Access")
                    } footer: {
                        Text("Turn this integration on to expose its tools to connected clients.")
                    }

                    HydrationPreferencesSection(service: appModel.hydrationService)

                    Section {
                        ForEach(appModel.hydrationService.tools()) { tool in
                            ServiceToolRow(tool: tool)
                        }
                    } header: {
                        Text("Available Tools")
                    } footer: {
                        Text("These tools become available when Hydration is enabled.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Hydration")
            } else {
                Text("Hydration service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HydrationPreferences: Equatable {
    var dailyGoalML: Int
    var defaultAmountML: Int
    var notificationIntervalMinutes: Int

    init(
        dailyGoalML: Int = 2_000,
        defaultAmountML: Int = 250,
        notificationIntervalMinutes: Int = 60
    ) {
        self.dailyGoalML = dailyGoalML
        self.defaultAmountML = defaultAmountML
        self.notificationIntervalMinutes = notificationIntervalMinutes
    }

    init(status: HydrationStatus) {
        self.init(
            dailyGoalML: status.dailyGoalML,
            defaultAmountML: status.defaultAmountML,
            notificationIntervalMinutes: status.notificationIntervalMinutes
        )
    }
}

private struct HydrationPreferencesSection: View {
    let service: HydrationToolService

    @State private var savedValues = HydrationPreferences()
    @State private var draftValues = HydrationPreferences()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        draftValues != savedValues
    }

    var body: some View {
        Section {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                LabeledContent("Daily Goal") {
                    Stepper(value: $draftValues.dailyGoalML, in: 250 ... 8_000, step: 100) {
                        Text("\(draftValues.dailyGoalML) mL")
                            .monospacedDigit()
                    }
                    .frame(width: 180, alignment: .trailing)
                }

                LabeledContent("Default Amount") {
                    Stepper(value: $draftValues.defaultAmountML, in: 50 ... 2_000, step: 50) {
                        Text("\(draftValues.defaultAmountML) mL")
                            .monospacedDigit()
                    }
                    .frame(width: 180, alignment: .trailing)
                }

                LabeledContent("Reminder Interval") {
                    Stepper(
                        value: $draftValues.notificationIntervalMinutes,
                        in: 15 ... 240,
                        step: 5
                    ) {
                        Text("\(draftValues.notificationIntervalMinutes) min")
                            .monospacedDigit()
                    }
                    .frame(width: 180, alignment: .trailing)
                }

                HStack {
                    Button("Reset Defaults") {
                        draftValues = HydrationPreferences()
                    }
                    .disabled(isSaving)

                    Spacer()

                    Button("Save") {
                        savePreferences()
                    }
                    .disabled(isSaving || !hasChanges)
                }
            }
        } header: {
            Text("Preferences")
        } footer: {
            Text("These values are used by Hydration tools for goals, quick logging, and reminders.")
        }
        .task {
            await loadPreferences()
        }
        .alert(
            "Unable to Save Hydration Settings",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func loadPreferences() async {
        do {
            let status = try await service.status()
            let values = HydrationPreferences(status: status)

            await MainActor.run {
                savedValues = values
                draftValues = values
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func savePreferences() {
        let values = draftValues
        isSaving = true

        Task {
            do {
                let status = try await service.updatePreferences(
                    dailyGoalML: values.dailyGoalML,
                    defaultAmountML: values.defaultAmountML,
                    notificationIntervalMinutes: values.notificationIntervalMinutes
                )
                let saved = HydrationPreferences(status: status)

                await MainActor.run {
                    savedValues = saved
                    draftValues = saved
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    let appModel = AppModel(autoStart: false)

    HydrationSettingView()
        .frame(width: 450)
        .environment(appModel)
}
