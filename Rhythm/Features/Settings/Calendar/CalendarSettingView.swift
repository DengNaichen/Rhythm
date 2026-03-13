import SwiftUI

struct CalendarSettingView: View {
    @State private var viewModel: CalendarSettingViewModel

    init(service: CalendarToolService) {
        _viewModel = State(initialValue: CalendarSettingViewModel(service: service))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Calendar Access", isOn: calendarAccessBinding)
                    .disabled(viewModel.isWorking)

                LabeledContent("Status") {
                    Text(viewModel.statusText)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Service Status")
            } footer: {
                Text("Enable this to allow Rhythm to use your system calendars.")
            }

            Section {
                ForEach(viewModel.tools) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                }
            } header: {
                Text("Available Tools")
            } footer: {
                Text("These tools are defined by the calendar integration.")
            }

            if viewModel.isServiceEnabled {
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
    }

    private var calendarAccessBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isServiceEnabled },
            set: { newValue in
                viewModel.setServiceEnabled(newValue)
            }
        )
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
    NavigationStack {
        CalendarSettingView(service: CalendarToolService())
    }
}
