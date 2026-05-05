import SwiftUI

struct StrengthStyleMetricField<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
            content()
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

struct StrengthSetRowEditor: View {
    /// Row index in the exercise (1-based), shown as #1, #2 — not the same as `setNumber` (repeat count).
    let lineOrdinal: Int
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
                Text("#\(lineOrdinal)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel("Prescription row number \(lineOrdinal)")

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Times")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Text("\(setNumber)×")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(minWidth: 26, alignment: .trailing)
                            .accessibilityLabel("Repeat this prescription \(setNumber) times")
                        Stepper("", value: $setNumber, in: 1...99)
                            .labelsHidden()
                            .controlSize(.small)
                            .accessibilityLabel("Number of times")
                            .accessibilityValue("\(setNumber)")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Plus and minus change how many times this row counts, not the row number.")

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
                StrengthStyleMetricField(title: "Reps") {
                    TextField("—", value: $reps, format: .number)
                        .keyboardType(.numberPad)
                }
                StrengthStyleMetricField(title: "kg") {
                    TextField("—", text: $weightKg)
                        .keyboardType(.decimalPad)
                }
                StrengthStyleMetricField(title: "RPE") {
                    TextField("—", text: $rpe)
                        .keyboardType(.decimalPad)
                }
                StrengthStyleMetricField(title: "Rest s") {
                    TextField("—", value: $restSec, format: .number)
                        .keyboardType(.numberPad)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
