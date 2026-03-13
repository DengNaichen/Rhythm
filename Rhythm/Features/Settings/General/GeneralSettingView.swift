//
//  GeneralSettingView.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//

import AppKit
import SwiftUI

struct GeneralSettingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section {
                Toggle("Allow Claude Desktop", isOn: allowClaudeBinding)
                Toggle("Allow OpenClaw", isOn: allowOpenClawBinding)
                Toggle("Allow Other MCP Clients", isOn: allowUnknownClientsBinding)
            } header: {
                Text("Client Access")
            } footer: {
                Text(
                    "Rhythm accepts connections from the desktop clients enabled here. Other clients stay blocked unless you explicitly allow them."
                )
            }

            Section {
                LabeledContent("OpenClaw") {
                    Button("Configure...") {
                        OpenClaw.showConfigurationPanel()
                    }
                }

                LabeledContent("Claude Desktop") {
                    Button("Configure...") {
                        ClaudeDesktop.showConfigurationPanel()
                    }
                }

                LabeledContent("Server Command") {
                    HStack(spacing: 8) {
                        Text(verbatim: appModel.serverCommand)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Copy") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(appModel.serverCommand, forType: .string)
                        }
                    }
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Write MCP settings for supported desktop clients.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .padding()
    }

    private var allowClaudeBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allows(.claudeDesktop) },
            set: { allowed in
                Task {
                    await appModel.setKnownClient(.claudeDesktop, allowed: allowed)
                }
            }
        )
    }

    private var allowOpenClawBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allows(.openClaw) },
            set: { allowed in
                Task {
                    await appModel.setKnownClient(.openClaw, allowed: allowed)
                }
            }
        )
    }

    private var allowUnknownClientsBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allowUnknownClients },
            set: { allowed in
                Task {
                    await appModel.setAllowUnknownClients(allowed)
                }
            }
        )
    }
}

#Preview {
    GeneralSettingView()
        .environment(AppModel())
}
