import SwiftUI

struct PetLogFilterSheet: View {
    @Binding var disabledCategories: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PetLogFilterCategory.allCases) { category in
                        Toggle(isOn: binding(for: category.rawValue)) {
                            Text(category.label)
                        }
                    }
                } footer: {
                    Text("Filters apply to loaded logs only.")
                }
            }
            .navigationTitle("Log filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show all") {
                        disabledCategories = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hide all") {
                        disabledCategories = Set(PetLogFilterCategory.allCases.map(\.rawValue))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { !disabledCategories.contains(key) },
            set: { enabled in
                if enabled {
                    disabledCategories.remove(key)
                } else {
                    disabledCategories.insert(key)
                }
            }
        )
    }
}
