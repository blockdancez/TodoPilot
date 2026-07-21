import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var copied = false

    var body: some View {
        let copy = environment.copy
        let report = environment.diagnosticsReporter.makeReport(
            taskStore: environment.taskStore,
            settingsStore: environment.settingsStore,
            copy: copy
        )

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.diagnostics)
                        .font(.largeTitle.weight(.semibold))
                    Text(copy.diagnosticsSubtitle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.asText, forType: .string)
                    copied = true
                    environment.logger.info("diagnostics_copied")
                } label: {
                    Label(copied ? copy.copied : copy.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                ForEach(report.items) { item in
                    GridRow {
                        Label(item.title, systemImage: item.systemImage)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Text(copy.diagnosticsPrivacyNote)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
        .accessibilityIdentifier("diagnostics.view")
    }
}
