import SwiftUI

func exerciseLanguageFromGlobalStorage() -> ExerciseLanguage {
    let raw = UserDefaults.standard.string(forKey: "exerciseLanguage")
        ?? ExerciseLanguage.spanish.rawValue
    return ExerciseLanguage(rawValue: raw) ?? .spanish
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
