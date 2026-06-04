import Foundation
import SwiftUI

func exerciseLanguageFromGlobalStorage() -> ExerciseLanguage {
    let raw = UserDefaults.standard.string(forKey: "exerciseLanguage")
        ?? ExerciseLanguage.spanish.rawValue
    return ExerciseLanguage(rawValue: raw) ?? .spanish
}

struct AppLanguage {
    static var preferredLanguageTag: String {
        if let tag = Bundle.main.preferredLocalizations.first, !tag.isEmpty {
            return tag
        }
        if let tag = Locale.preferredLanguages.first, !tag.isEmpty {
            return tag
        }
        return ""
    }

    static var isSpanish: Bool {
        preferredLanguageTag.lowercased().hasPrefix("es")
    }
}

struct FieldRowPlain<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        LabeledContent {
            content
                .labelsHidden()
        } label: {
            if let title {
                Text(title)
            }
        }
        .padding(.vertical, 10)
    }
}

struct FormNoteTextField: View {
    @Binding var text: String
    var placeholder: String
    var lineRange: ClosedRange<Int> = 2...18

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(lineRange)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WorkoutMetricField<Content: View>: View {
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

typealias StrengthStyleMetricField = WorkoutMetricField

struct WorkoutDurationHMSFields: View {
    @Binding var hours: String
    @Binding var minutes: String
    @Binding var seconds: String
    var onAnyChange: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            WorkoutMetricField(title: "h") {
                TextField("—", text: $hours)
                    .keyboardType(.numberPad)
                    .onChange(of: hours) { _, _ in onAnyChange() }
            }
            WorkoutMetricField(title: "m") {
                TextField("—", text: $minutes)
                    .keyboardType(.numberPad)
                    .onChange(of: minutes) { _, _ in onAnyChange() }
            }
            WorkoutMetricField(title: "s") {
                TextField("—", text: $seconds)
                    .keyboardType(.numberPad)
                    .onChange(of: seconds) { _, _ in onAnyChange() }
            }
        }
    }
}

struct WorkoutMetricReadoutField: View {
    let title: String
    let value: String

    var body: some View {
        WorkoutMetricField(title: title) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value == "—" ? Color.secondary : Color.primary)
        }
    }
}

struct WorkoutMetricFieldsRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            content()
        }
        .padding(.vertical, 4)
    }
}

@ViewBuilder
func workoutMetricField(
    _ title: String,
    text: Binding<String>,
    keyboard: UIKeyboardType = .numberPad,
    onEdit: (() -> Void)? = nil
) -> some View {
    WorkoutMetricField(title: title) {
        TextField("—", text: text)
            .keyboardType(keyboard)
            .onChange(of: text.wrappedValue) { _, _ in onEdit?() }
    }
}

struct FieldRowNotes: View {
    var title: String
    @Binding var text: String
    var placeholder: String
    var lineRange: ClosedRange<Int> = 2...18

    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        lineRange: ClosedRange<Int> = 2...18
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.lineRange = lineRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body)
            FormNoteTextField(text: $text, placeholder: placeholder, lineRange: lineRange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}
