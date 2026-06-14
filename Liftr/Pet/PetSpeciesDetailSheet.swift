import SwiftUI

struct PetSpeciesDetailSheet: View {
    let petType: String
    var showsDexStats: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var detail: PetSpeciesDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let stageColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading species...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                } else if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerSection(detail)
                            stagesSection(detail)
                            if showsDexStats, let dex = detail.dex {
                                dexStatsSection(dex)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .gradientBG()
        .task { await load() }
    }

    @ViewBuilder
    private func headerSection(_ detail: PetSpeciesDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.displayName.isEmpty ? detail.petType.petDisplayTitle : detail.displayName)
                .font(.title2.weight(.semibold))

            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stagesSection(_ detail: PetSpeciesDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Evolution stages")
                .font(.headline)

            Text("Stages unlock when you evolve your own pet to them or fight that stage in the arena.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: stageColumns, spacing: 10) {
                ForEach(PetEvolutionStages.ordered, id: \.self) { stage in
                    stageCard(detail: detail, stage: stage)
                }
            }
        }
    }

    @ViewBuilder
    private func stageCard(detail: PetSpeciesDetail, stage: String) -> some View {
        let discovered = detail.isStageDiscovered(stage)

        VStack(spacing: 6) {
            ZStack {
                if discovered, let url = detail.imageURL(for: stage) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "pawprint.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                    .frame(height: 64)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black.opacity(0.35))
                        .frame(height: 64)
                        .overlay {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                }
            }

            Text(PetEvolutionStages.displayName(for: stage))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(discovered ? .primary : .secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func dexStatsSection(_ dex: PetDexStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Arena record")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Battles: \(dex.totalBattles) (\(dex.wins)W-\(dex.losses)L-\(dex.draws)D)")
                if !dex.raritiesSeen.isEmpty {
                    Text("Rarities faced: \(dex.raritiesSeen.map { $0.capitalized }.joined(separator: ", "))")
                }
                if !dex.stagesSeen.isEmpty {
                    Text("Stages faced: \(dex.stagesSeen.map { PetEvolutionStages.displayName(for: $0) }.joined(separator: ", "))")
                }
                if let first = dex.firstFoughtAt {
                    Text("First fought: \(first.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let last = dex.lastFoughtAt {
                    Text("Last fought: \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = detail == nil
        errorMessage = nil
        do {
            detail = try await PetService.shared.fetchPetSpeciesDetail(petType: petType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
