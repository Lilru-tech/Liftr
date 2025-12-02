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
