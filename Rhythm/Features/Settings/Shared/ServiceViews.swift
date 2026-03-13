import SwiftUI

struct ServiceToggleView: View {
    @Environment(AppModel.self) private var appModel

    let config: ServiceConfig
    var onStateChanged: (() -> Void)? = nil

    @State private var isServiceActivated = false
    @State private var isActivating = false

    private enum Metrics {
        static let contentSpacing: CGFloat = 8
        static let iconWidth: CGFloat = 18
        static let iconTopPadding: CGFloat = 2
        static let labelVerticalPadding: CGFloat = 2
    }

    var body: some View {
        Toggle(isOn: toggleBinding) {
            HStack(alignment: .top, spacing: Metrics.contentSpacing) {
                Image(systemName: config.iconName)
                    .foregroundStyle(appModel.isServiceEnabled(config.id) ? config.color : .secondary)
                    .frame(width: Metrics.iconWidth)
                    .padding(.top, Metrics.iconTopPadding)

                VStack(alignment: .leading, spacing: Metrics.labelVerticalPadding) {
                    Text(config.name)
                        .font(.body)

                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Metrics.labelVerticalPadding)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .disabled(isActivating)
        .task {
            isServiceActivated = await appModel.refreshActivationState(
                for: config.id,
                syncEnabledState: true
            )
        }
    }

    private var statusText: String {
        if isActivating {
            return "Requesting Access"
        }

        if !isServiceActivated {
            return "Needs Access"
        }

        return appModel.isServiceEnabled(config.id) ? "Ready" : "Inactive"
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { appModel.isServiceEnabled(config.id) && isServiceActivated },
            set: { newValue in
                guard newValue else {
                    Task {
                        await appModel.setServiceEnabled(false, for: config.id)
                        await MainActor.run {
                            onStateChanged?()
                        }
                    }
                    return
                }

                guard !isActivating else {
                    return
                }

                guard !isServiceActivated else {
                    Task {
                        await appModel.setServiceEnabled(true, for: config.id)
                        await MainActor.run {
                            onStateChanged?()
                        }
                    }
                    return
                }

                isActivating = true

                Task {
                    let activated = await appModel.activateService(config.id)

                    await MainActor.run {
                        isActivating = false
                        isServiceActivated = activated
                    }

                    await appModel.setServiceEnabled(activated, for: config.id)

                    await MainActor.run {
                        onStateChanged?()
                    }
                }
            }
        )
    }
}

struct ServiceToolRow: View {
    let tool: Tool

    private var badges: [String] {
        var values: [String] = []

        if tool.annotations.readOnlyHint == true {
            values.append("Read Only")
        } else {
            values.append("Action")
        }

        if tool.annotations.destructiveHint == true {
            values.append("Destructive")
        }

        if tool.annotations.idempotentHint == true {
            values.append("Repeatable")
        }

        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tool.title)
                .font(.body.weight(.medium))

            Text(tool.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    ToolCapabilityBadge(title: badge)
                }
            }

            Text(verbatim: tool.name)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ToolCapabilityBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }
}
