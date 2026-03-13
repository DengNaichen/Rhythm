import SwiftUI

struct ThingsSettingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let config = appModel.serviceConfig(for: .things) {
                Form {
                    Section {
                        ServiceToggleView(config: config)
                    } header: {
                        Text("Access")
                    } footer: {
                        Text("Turn this integration on to expose its tools to connected clients.")
                    }

                    Section {
                        ForEach(appModel.thingsService.tools()) { tool in
                            ServiceToolRow(tool: tool)
                        }
                    } header: {
                        Text("Available Tools")
                    } footer: {
                        Text("These tools become available when Things is enabled.")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Things")
            } else {
                Text("Things service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let appModel = AppModel(autoStart: false)

    ThingsSettingView()
        .environment(appModel)
}
