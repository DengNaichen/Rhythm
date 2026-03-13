import SwiftUI

struct CalendarSettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: CalendarSettingViewModel

    init(service: CalendarToolService) {
        _viewModel = State(initialValue: CalendarSettingViewModel(service: service))
    }

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .calendar) {
                Form {
                    Section {
                        ServiceToggleView(config: config) {
                            Task {
                                await viewModel.load()
                            }
                        }
                    } header: {
                        Text("Access")
                    } footer: {
                        Text("Turn this integration on to expose its tools to connected clients.")
                    }

                    Section {
                        ForEach(viewModel.tools) { tool in
                            ServiceToolRow(tool: tool)
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
}

#Preview {
    let appModel = AppModel(autoStart: false)

    NavigationStack {
        CalendarSettingView(service: CalendarToolService())
    }
    .environment(appModel)
}
