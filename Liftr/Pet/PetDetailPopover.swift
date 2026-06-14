import SwiftUI

struct PetDetailPopover: View {
    @ObservedObject var viewModel: PetDetailViewModel
    let onClose: () -> Void

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var showStatCombatHelp = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Pet")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if viewModel.isLoading && viewModel.data == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let pet = viewModel.data?.pet {
                ScrollView {
                    VStack(spacing: 14) {
                        petHeader(pet)
                        if pet.isIncubatingEgg {
                            incubationSection(pet)
                        } else if pet.isPendingHatch {
                            Text("Hatching soon...")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else if pet.evolutionStage.lowercased() != "egg" {
                            hatchedSection(pet)
                        }
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                Text("No active pet yet. Visit the Market to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .onReceive(timer) { now = $0 }
        .onAppear {
            Task {
                await viewModel.load()
                viewModel.startPollingIfNeeded()
            }
        }
        .onDisappear { viewModel.stopPolling() }
        .sheet(isPresented: $showStatCombatHelp) {
            PetStatCombatHelpSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func petHeader(_ pet: PetInstanceRow) -> some View {
        VStack(spacing: 8) {
            PetAsyncImage(pet: pet, height: 96)

            HStack {
                if isEditingName {
                    TextField("Pet name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task {
                                await viewModel.updateName(draftName)
                                isEditingName = false
                            }
                        }
                } else {
                    Text(pet.displayTitle)
                        .font(.title3.bold())
                    Button {
                        draftName = pet.customName ?? ""
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                }
            }

            PetRarityBadge(rarity: pet.rarityEnum)
        }
    }

    @ViewBuilder
    private func incubationSection(_ pet: PetInstanceRow) -> some View {
        VStack(spacing: 8) {
            Text("Hatching in")
                .font(.subheadline.weight(.semibold))
            if let hatchAt = pet.hatchAt {
                Text(hatchAt, style: .timer)
                    .font(.system(.title2, design: .monospaced).bold())
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                Text("Species: \(pet.petType.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Reroll egg") {
                Task { await viewModel.rerollEgg() }
            }
            .buttonStyle(.bordered)
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func hatchedSection(_ pet: PetInstanceRow) -> some View {
        let xpRequired = max(1, viewModel.data?.xpRequired ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Level \(pet.currentLevel)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(pet.currentXp) / \(xpRequired) XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(pet.currentXp), total: Double(xpRequired))

            if viewModel.data?.canEvolve == true {
                Button {
                    Task { await viewModel.confirmEvolution() }
                } label: {
                    HStack {
                        if viewModel.isEvolving { ProgressView().controlSize(.small) }
                        Text("Evolve to next stage")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let stats = viewModel.data?.stats {
                HStack {
                    Text("Stats")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        showStatCombatHelp = true
                    } label: {
                        PetStatCombatHelpButton()
                    }
                    .buttonStyle(.plain)
                }
                statsGrid(stats)
            }

            foodBar
        }
    }

    @ViewBuilder
    private func statsGrid(_ stats: PetStatsRow) -> some View {
        let pairs: [(String, Int)] = [
            ("Health", stats.health), ("Strength", stats.strength), ("Defense", stats.defense),
            ("Speed", stats.speed), ("Intelligence", stats.intelligence), ("Agility", stats.agility),
            ("Stamina", stats.stamina), ("Crit", stats.criticalRate), ("Resistance", stats.resistance),
            ("Explore", stats.exploration), ("Happiness", stats.happiness)
        ]
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(pairs, id: \.0) { label, value in
                HStack {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(value)").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var foodBar: some View {
        let foods = (viewModel.data?.inventory ?? []).filter { PetFoodItemType.all.contains($0.itemType) && $0.quantity > 0 }
        VStack(alignment: .leading, spacing: 8) {
            Text("Food")
                .font(.subheadline.weight(.semibold))
            if foods.isEmpty {
                Text("No food in inventory. Buy some in the Market.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(foods) { item in
                            Button {
                                Task { await viewModel.feed(itemType: item.itemType) }
                            } label: {
                                VStack(spacing: 4) {
                                    AsyncImage(url: PetImageURLBuilder.marketItemURL(path: "market/\(item.itemType).png")) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFit().frame(width: 36, height: 36)
                                        } else {
                                            Image(systemName: "leaf.fill")
                                        }
                                    }
                                    Text("×\(item.quantity)")
                                        .font(.caption2.bold())
                                }
                                .padding(8)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isFeeding)
                        }
                    }
                }
            }
        }
    }
}
