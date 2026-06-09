import SwiftUI

struct PetAsyncImage: View {
    let pet: PetInstanceRow
    var height: CGFloat = 120
    var padding: CGFloat = 0
    var showRarityRing: Bool = false

    @State private var candidateIndex = 0

    private var candidates: [URL] {
        pet.imageURLCandidates
    }

    private var currentURL: URL? {
        guard candidateIndex < candidates.count else { return nil }
        return candidates[candidateIndex]
    }

    var body: some View {
        Group {
            if let url = currentURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: height)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(padding)
                            .frame(height: height)
                            .overlay(rarityRing)
                    case .failure:
                        Group {
                            if candidateIndex + 1 < candidates.count {
                                Color.clear
                                    .frame(height: height)
                                    .onAppear { advanceCandidate() }
                            } else {
                                placeholder
                            }
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholder
            }
        }
        .onChange(of: pet.id) { _, _ in candidateIndex = 0 }
        .onChange(of: pet.imageUrl) { _, _ in candidateIndex = 0 }
        .onChange(of: pet.evolutionStage) { _, _ in candidateIndex = 0 }
    }

    @ViewBuilder
    private var rarityRing: some View {
        if showRarityRing {
            Circle()
                .stroke(pet.rarityEnum.color.opacity(0.5), lineWidth: 3)
                .frame(width: height + 10, height: height + 10)
        }
    }

    private var placeholder: some View {
        Image(systemName: "oval.fill")
            .font(.system(size: min(height * 0.45, 48)))
            .foregroundStyle(.secondary)
            .frame(height: height)
    }

    private func advanceCandidate() {
        guard candidateIndex + 1 < candidates.count else { return }
        candidateIndex += 1
    }
}
