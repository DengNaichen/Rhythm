import SwiftUI
import SwiftData

struct SettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedSection: SettingSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SettingSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedSection {
            case .general:
                GeneralSettingView()
            case .calendar:
                CalendarSettingView(service: appModel.calendarService)
            case .reminders:
                ReminderSettingView()
            case .things:
                ThingsSettingView()
            case .hydration:
                HydrationSettingView()
            case .about:
                AboutView()
            case .none:
                Text("Select an item")
            }
        }
    }
}

#Preview {
    SettingView()
        .environment(AppModel())
        .modelContainer(for: Item.self, inMemory: true)
}
