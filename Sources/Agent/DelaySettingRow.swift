import SwiftUI

/// Keep the explanation above the controls so the slider and unit fit even in a narrow window.
struct DelaySettingRow: View {
    let title: String
    let explanation: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Slider(value: $value, in: FolderPrefs.hoverDelayRange)
                    .labelsHidden()
                    .accessibilityLabel(title)
                TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityLabel(L10n.format("%@ in seconds", title))
                Text(L10n.text("s"))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
