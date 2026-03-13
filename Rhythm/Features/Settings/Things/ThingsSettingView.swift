import SwiftUI

struct ThingsSettingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isThingsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Things Access", isOn: $isThingsEnabled)
            } header: {
                Text("Service Status")
            } footer: {
                Text("Enable this to allow Rhythm to use your Things database and URL actions.")
            }

            Section {
                ForEach(appModel.thingsService.tools()) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                }
            } header: {
                Text("Available Tools")
            } footer: {
                Text("These tools are exposed by the Things MCP service.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Things")
    }
}

#Preview {
    ThingsSettingView()
        .environment(AppModel())
}
