import SwiftUI

struct SettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gear")
                    .tag(SettingsDestination.general)

                if !appModel.visibleServiceConfigs.isEmpty {
                    Section("Services") {
                        ForEach(appModel.visibleServiceConfigs) { config in
                            Label(config.name, systemImage: config.iconName)
                                .tag(SettingsDestination.service(config.id))
                        }
                    }
                }

                Label("About", systemImage: "info.circle")
                    .tag(SettingsDestination.about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: SettingsMetrics.sidebarWidth,
                ideal: SettingsMetrics.sidebarWidth
            )
        } detail: {
            detailView(for: selection ?? .general)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            GeneralSettingView()
        case let .service(serviceID):
            serviceDetailView(for: serviceID)
        case .about:
            AboutView()
        }
    }

    @ViewBuilder
    private func serviceDetailView(for serviceID: ServiceID) -> some View {
        switch serviceID {
        case .calendar:
            CalendarSettingView(service: appModel.calendarService)
        case .hydration:
            HydrationSettingView()
        case .reminders:
            ReminderSettingView()
        case .things:
            ThingsSettingView()
        }
    }
}

private enum SettingsDestination: Hashable {
    case general
    case service(ServiceID)
    case about
}

#Preview {
    SettingView()
        .environment(AppModel(autoStart: false))
}
