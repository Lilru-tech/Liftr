import SwiftUI

struct PetInventoryItemOverlay: View {
    let item: PetInventoryDisplayItem
    let hasIncubator: Bool
    let canIncubate: Bool
    let onClose: () -> Void
    let onIncubate: () async -> Void

    @State private var isIncubating = false
    @State private var errorMessage: String?

    private var isEgg: Bool { item.itemType == "pet_egg" }
    private var isIncubator: Bool { item.itemType == "incubator" }

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit().frame(height: 120)
                default:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(height: 120)
                }
            }

            Text(item.displayName)
                .font(.title2.bold())

            Text(item.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if item.quantity > 1 {
                Text("Owned: \(item.quantity)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Already bought")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if isEgg {
                Button {
                    Task {
                        isIncubating = true
                        defer { isIncubating = false }
                        await onIncubate()
                    }
                } label: {
                    HStack {
                        if isIncubating { ProgressView().controlSize(.small) }
                        Text("Incubate")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canIncubate || isIncubating)

                if !hasIncubator {
                    Text("You need an Egg Incubator to incubate this egg.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else if isIncubator {
                Text("Used when you incubate your Mysterious Egg.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Close", action: onClose)
                .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
    }
}
