import SwiftUI

struct CalendarSettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: CalendarSettingViewModel
    @State private var isServiceActivated = false
    @State private var isActivating = false

    init(service: CalendarToolService) {
        _viewModel = State(initialValue: CalendarSettingViewModel(service: service))
    }

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .calendar) {
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
                        ForEach(viewModel.tools) { tool in
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
                        Text("These tools become available when Calendar is enabled.")
                    }

                    if appModel.isServiceEnabled(.calendar) && viewModel.isServiceEnabled {
                        Section {
                            Button("Refresh Events") {
                                viewModel.refreshEvents()
                            }
                            .disabled(viewModel.isWorking || viewModel.isLoadingEvents)

                            if viewModel.isLoadingEvents {
                                HStack {
                                    Spacer()
                                    ProgressView("Loading Events...")
                                    Spacer()
                                }
                            } else if viewModel.events.isEmpty {
                                Text("No events scheduled in the next 7 days.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.events) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .font(.body.weight(.medium))

                                        Text(viewModel.dayText(for: event))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(viewModel.timeText(for: event))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(event.listTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)

                                        if let location = event.location {
                                            Text(location)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Text("Upcoming Events")
                        } footer: {
                            Text("Showing events from the next 7 days.")
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Calendar")
                .task {
                    isServiceActivated = await appModel.refreshActivationState(
                        for: .calendar,
                        syncEnabledState: true
                    )
                    await viewModel.load()
                }
                .alert(
                    "Calendar Access Failed",
                    isPresented: errorAlertBinding
                ) {
                    Button("OK") {
                        viewModel.clearError()
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
            } else {
                Text("Calendar service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearError()
                }
            }
        )
    }

    private var statusText: String {
        if isActivating {
            return "Requesting Access"
        }

        if viewModel.isLoadingEvents {
            return "Loading Events"
        }

        if !isServiceActivated {
            return "Needs Access"
        }

        return appModel.isServiceEnabled(.calendar) ? "Ready" : "Inactive"
    }

    private var serviceToggleBinding: Binding<Bool> {
        Binding(
            get: { appModel.isServiceEnabled(.calendar) && isServiceActivated },
            set: { newValue in
                guard newValue else {
                    Task {
                        await appModel.setServiceEnabled(false, for: .calendar)
                        await viewModel.load()
                    }
                    return
                }

                guard !isActivating else {
                    return
                }

                guard !isServiceActivated else {
                    Task {
                        await appModel.setServiceEnabled(true, for: .calendar)
                        await viewModel.load()
                    }
                    return
                }

                isActivating = true

                Task {
                    let activated = await appModel.activateService(.calendar)

                    await MainActor.run {
                        isActivating = false
                        isServiceActivated = activated
                    }

                    await appModel.setServiceEnabled(activated, for: .calendar)
                    await viewModel.load()
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

    NavigationStack {
        CalendarSettingView(service: CalendarToolService())
    }
    .environment(appModel)
}
