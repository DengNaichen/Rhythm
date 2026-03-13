import SwiftUI

struct ReminderSettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isServiceActivated = false
    @State private var isActivating = false

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .reminders) {
                Form {
                    Section {
                        Toggle("Enable \(config.name)", isOn: serviceToggleBinding)
                            .disabled(isActivating)

                        LabeledContent("Status") {
                            Text(statusText)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Access")
                    } footer: {
                        Text("Turn this integration on to expose its tools to connected clients.")
                    }

                    Section {
                        ForEach(appModel.remindersService.tools()) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.title)
                                    .font(.body.weight(.medium))

                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(toolSummary(for: tool))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                Text(verbatim: tool.name)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Available Tools")
                    } footer: {
                        Text("These tools become available when Reminders is enabled.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Reminders")
                .task {
                    isServiceActivated = await appModel.refreshActivationState(
                        for: .reminders,
                        syncEnabledState: true
                    )
                }
            } else {
                Text("Reminders service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if isActivating {
            return "Requesting Access"
        }

        if !isServiceActivated {
            return "Needs Access"
        }

        return appModel.isServiceEnabled(.reminders) ? "Ready" : "Inactive"
    }

    private var serviceToggleBinding: Binding<Bool> {
        Binding(
            get: { appModel.isServiceEnabled(.reminders) && isServiceActivated },
            set: { newValue in
                guard newValue else {
                    Task {
                        await appModel.setServiceEnabled(false, for: .reminders)
                    }
                    return
                }

                guard !isActivating else {
                    return
                }

                guard !isServiceActivated else {
                    Task {
                        await appModel.setServiceEnabled(true, for: .reminders)
                    }
                    return
                }

                isActivating = true

                Task {
                    let activated = await appModel.activateService(.reminders)

                    await MainActor.run {
                        isActivating = false
                        isServiceActivated = activated
                    }

                    await appModel.setServiceEnabled(activated, for: .reminders)
                }
            }
        )
    }

    private func toolSummary(for tool: Tool) -> String {
        var values: [String] = []

        if tool.annotations.readOnlyHint == true {
            values.append("Read Only")
        } else {
            values.append("Action")
        }

        if tool.annotations.destructiveHint == true {
            values.append("Destructive")
        }

        if tool.annotations.idempotentHint == true {
            values.append("Repeatable")
        }

        return values.joined(separator: " • ")
    }
}

#Preview {
    let appModel = AppModel(autoStart: false)

    ReminderSettingView()
        .environment(appModel)
}
