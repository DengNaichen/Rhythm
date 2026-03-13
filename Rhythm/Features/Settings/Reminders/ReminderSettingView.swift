import SwiftUI

struct ReminderSettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isReminderEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Reminder Access", isOn: $isReminderEnabled)
            } header: {
                Text("Service Status")
            } footer: {
                Text("Enable this to allow Rhythm to use your system reminders.")
            }

            Section {
                ForEach(appModel.remindersService.tools()) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                }
            } header: {
                Text("Available Tools")
            } footer: {
                Text("These tools are exposed by the reminders MCP service.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reminders")
    }
}

#Preview {
    ReminderSettingView()
        .environment(AppModel())
}
