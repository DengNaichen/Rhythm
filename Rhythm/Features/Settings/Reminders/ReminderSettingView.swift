import SwiftUI

struct ReminderSettingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .reminders) {
                Form {
                    Section {
                        ServiceToggleView(config: config)
                    } header: {
                        Text("Access")
                    } footer: {
                        Text("Turn this integration on to expose its tools to connected clients.")
                    }

                    Section {
                        ForEach(appModel.remindersService.tools()) { tool in
                            ServiceToolRow(tool: tool)
                        }
                    } header: {
                        Text("Available Tools")
                    } footer: {
                        Text("These tools become available when Reminders is enabled.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Reminders")
            } else {
                Text("Reminders service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let appModel = AppModel(autoStart: false)

    ReminderSettingView()
        .environment(appModel)
}
