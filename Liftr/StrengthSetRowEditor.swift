import Foundation
import Supabase
import SwiftUI

struct StrengthWeightSegWire: Codable, Hashable {
    let reps: Int
    let weight_kg: Double
}

extension Array where Element == StrengthWeightSegWire {
    func asEditorSegmentsIfDropSet() -> [StrengthEditorSegment] {
        guard count >= 2 else { return [] }
        return map { w in
            let str = w.weight_kg == floor(w.weight_kg) ? String(Int(w.weight_kg)) : String(format: "%.1f", w.weight_kg)
            return StrengthEditorSegment(reps: w.reps, weightKg: str)
        }
    }
}

struct StrengthEditorSegment: Identifiable, Hashable {
    let id: UUID
    var reps: Int?
    var weightKg: String

    init(id: UUID = UUID(), reps: Int?, weightKg: String) {
        self.id = id
        self.reps = reps
        self.weightKg = weightKg
    }
}

extension Array where Element == StrengthEditorSegment {
    func encodedWeightSegmentsOrNil() throws -> AnyJSON? {
        guard count >= 2 else { return nil }
        var elems: [AnyJSON] = []
        for seg in self {
            guard let r = seg.reps, r > 0 else { return nil }
            let t = seg.weightKg.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let w = Double(t) else { return nil }
            let obj: [String: AnyJSON] = [
                "reps": try AnyJSON(r),
                "weight_kg": try AnyJSON(w)
            ]
            elems.append(try AnyJSON(obj))
        }
        guard elems.count == count else { return nil }
        return try AnyJSON(elems)
    }
}

struct StrengthSetRowEditor: View {
    let lineOrdinal: Int
    @Binding var setNumber: Int
    @Binding var reps: Int?
    @Binding var weightKg: String
    @Binding var rpe: String
    @Binding var restSec: Int?
    @Binding var segments: [StrengthEditorSegment]
    var showDelete: Bool
    var showReorder: Bool = false
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onDelete: () -> Void

    private var isDrop: Bool { segments.count >= 2 }

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

                if showReorder {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveUp)
                        .opacity(canMoveUp ? 1 : 0.35)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveDown)
                        .opacity(canMoveDown ? 1 : 0.35)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reorder set")
                }

                if showDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove set")
                }
            }

            if isDrop {
                ForEach(Array(segments.enumerated()), id: \.1.id) { pair in
                    let idx = pair.0
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                            .accessibilityLabel("Drop step \(idx + 1)")
                        StrengthStyleMetricField(title: "Reps") {
                            TextField(
                                "—",
                                value: Binding(
                                    get: { segments[idx].reps },
                                    set: { segments[idx].reps = $0 }
                                ),
                                format: .number
                            )
                            .keyboardType(.numberPad)
                        }
                        StrengthStyleMetricField(title: "kg") {
                            TextField(
                                "—",
                                text: Binding(
                                    get: { segments[idx].weightKg },
                                    set: { segments[idx].weightKg = $0 }
                                )
                            )
                            .keyboardType(.decimalPad)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("Add step") {
                        segments.append(StrengthEditorSegment(reps: nil, weightKg: ""))
                    }
                    .buttonStyle(.borderless)
                    .disabled(segments.count >= 12)
                    Button("Remove step") {
                        if segments.count > 2 { segments.removeLast() }
                    }
                    .buttonStyle(.borderless)
                    .disabled(segments.count <= 2)
                    Button("Clear drop") {
                        segments = []
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption.weight(.semibold))
                HStack(alignment: .top, spacing: 6) {
                    StrengthStyleMetricField(title: "RPE") {
                        TextField("—", text: $rpe)
                            .keyboardType(.decimalPad)
                    }
                    StrengthStyleMetricField(title: "Rest s") {
                        TextField("—", value: $restSec, format: .number)
                            .keyboardType(.numberPad)
                    }
                }
            } else {
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
                Button("Drop set") {
                    let w = weightKg.trimmingCharacters(in: .whitespacesAndNewlines)
                    segments = [
                        StrengthEditorSegment(reps: reps, weightKg: w),
                        StrengthEditorSegment(reps: nil, weightKg: "")
                    ]
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
