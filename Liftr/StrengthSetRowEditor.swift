import SwiftUI

struct StrengthSetRowEditor: View {
    @Binding var setNumber: Int
    @Binding var reps: Int?
    @Binding var weightKg: String
    @Binding var rpe: String
    @Binding var restSec: Int?
    var showDelete: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Set \(setNumber)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Stepper("", value: $setNumber, in: 1...99)
                    .labelsHidden()
                    .controlSize(.small)

                Spacer(minLength: 8)

                if showDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove set")
                }
            }

            HStack(alignment: .top, spacing: 6) {
                metricCell(title: "Reps") {
                    TextField("—", value: $reps, format: .number)
                        .keyboardType(.numberPad)
                }
                metricCell(title: "kg") {
                    TextField("—", text: $weightKg)
                        .keyboardType(.decimalPad)
                }
                metricCell(title: "RPE") {
                    TextField("—", text: $rpe)
                        .keyboardType(.decimalPad)
                }
                metricCell(title: "Rest s") {
                    TextField("—", value: $restSec, format: .number)
                        .keyboardType(.numberPad)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metricCell<Inner: View>(title: String, @ViewBuilder field: () -> Inner) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            field()
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}
