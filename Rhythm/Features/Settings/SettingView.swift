import SwiftUI

struct SettingView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsStorageKey.selectedSection)
    private var selectedSectionRawValue = SettingsSection.general.storageValue

    private var serviceConfigs: [ServiceConfig] {
        appModel.visibleServiceConfigs
    }

    private var availableServiceIDs: Set<ServiceID> {
        Set(serviceConfigs.map(\.id))
    }

    private var selectedSectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { resolvedSelectedSection },
            set: { newValue in
                selectedSectionRawValue = (newValue ?? .general).storageValue
            }
        )
    }

    private var resolvedSelectedSection: SettingsSection {
        let section = SettingsSection(storageValue: selectedSectionRawValue)

        switch section {
        case .service(let serviceID) where !availableServiceIDs.contains(serviceID):
            return .general
        default:
            return section
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedSectionBinding) {
                SettingsSidebarRow(title: "General", systemImage: "gear")
                    .tag(SettingsSection.general)

                if !serviceConfigs.isEmpty {
                    Section("Services") {
                        ForEach(serviceConfigs) { config in
                            SettingsSidebarRow(title: config.name, systemImage: config.iconName)
                                .tag(SettingsSection.service(config.id))
                        }
                    }
                }

                SettingsSidebarRow(title: "About", systemImage: "info.circle")
                    .tag(SettingsSection.about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: SettingsMetrics.sidebarWidth,
                ideal: SettingsMetrics.sidebarWidth
            )
        } detail: {
            settingsDetailView(for: resolvedSelectedSection)
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: serviceConfigs.map(\.id)) {
            selectedSectionRawValue = resolvedSelectedSection.storageValue
        }
    }

    @ViewBuilder
    private func settingsDetailView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingView()
        case .service(let serviceID):
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
        case .about:
            AboutView()
        }
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

#Preview {
    SettingView()
        .environment(AppModel(autoStart: false))
}
