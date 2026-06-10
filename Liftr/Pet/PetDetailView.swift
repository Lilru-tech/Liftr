import SwiftUI

struct PetDetailView: View {
    @ObservedObject var viewModel: PetDetailViewModel
    @ObservedObject private var coinManager = CoinManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var selectedTab = "Inventory"
    @State private var statsExpanded = true
    @State private var recordsExpanded = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.data == nil {
                    ProgressView("Loading pet...")
                        .padding(.top, 40)
                } else if let pet = viewModel.data?.pet {
                    VStack(spacing: 16) {
                        headerSection(pet)
                        petImage(pet)

                        if pet.isEggStage {
                            eggSection(pet)
                            Divider().padding(.top, 8)
                            PetLogsView(
                                logs: viewModel.logs,
                                hasMore: viewModel.hasMoreLogs,
                                onLoadMore: { Task { await viewModel.loadMoreLogs() } },
                                onDeleteAll: { Task { await viewModel.deleteAllLogs() } }
                            )
                        } else {
                            hatchedSection(pet)
                            Divider()
                            Picker("Tab", selection: $selectedTab) {
                                Text("Inventory").tag("Inventory")
                                Text("Logs").tag("Logs")
                            }
                            .pickerStyle(.segmented)

                            if selectedTab == "Inventory" {
                                foodBar
                            } else {
                                PetLogsView(
                                    logs: viewModel.logs,
                                    hasMore: viewModel.hasMoreLogs,
                                    onLoadMore: { Task { await viewModel.loadMoreLogs() } },
                                    onDeleteAll: { Task { await viewModel.deleteAllLogs() } }
                                )
                            }
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Text("No active pet yet. Visit the Market to get started.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if hasAppeared {
                    Task {
                        await viewModel.load()
                        await coinManager.refreshBalance(notifyIfEarned: false)
                    }
                }
                hasAppeared = true
            }
        }
        .gradientBG()
        .task {
            await viewModel.load()
            await viewModel.reloadLogs()
            await coinManager.refreshBalance(notifyIfEarned: false)
            viewModel.startPollingIfNeeded()
        }
        .onDisappear { viewModel.stopPolling() }
    }

    @ViewBuilder
    private func headerSection(_ pet: PetInstanceRow) -> some View {
        VStack(spacing: 8) {
            if isEditingName {
                TextField("Pet name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        Task {
                            await viewModel.updateName(draftName)
                            isEditingName = false
                        }
                    }
                HStack(spacing: 16) {
                    Button("Cancel") { isEditingName = false }
                    Button("Save") {
                        Task {
                            await viewModel.updateName(draftName)
                            isEditingName = false
                        }
                    }
                    .fontWeight(.semibold)
                }
            } else {
                HStack(spacing: 8) {
                    Text(displayName(for: pet))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Button {
                        draftName = pet.customName ?? ""
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                PetRarityBadge(rarity: pet.rarityEnum)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func petImage(_ pet: PetInstanceRow) -> some View {
        PetAsyncImage(
            pet: pet,
            height: 120,
            showRarityRing: true
        )
    }

    private func displayName(for pet: PetInstanceRow) -> String {
        if let customName = pet.customName, !customName.isEmpty { return customName }
        return titleForStage(pet.evolutionStage)
    }

    @ViewBuilder
    private func eggSection(_ pet: PetInstanceRow) -> some View {
        VStack(spacing: 10) {
            if pet.isPendingHatch {
                Text("Hatching soon...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if let hatchAt = pet.hatchAt {
                Text("Will hatch at: \(hatchAt.formatted(date: .numeric, time: .shortened))")
                    .font(.subheadline)
            }

            Text("Type: \(pet.petType.petDisplayTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Your coins: \(coinManager.balance)")
                .font(.caption)
                .foregroundStyle(.yellow)

            Button {
                Task { await viewModel.rerollEgg() }
            } label: {
                HStack {
                    if viewModel.isRerolling { ProgressView().controlSize(.small) }
                    Label("Change Pet", systemImage: "arrow.triangle.2.circlepath")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
            .background(Color.red.opacity(0.2))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(viewModel.isRerolling || pet.isPendingHatch)

            Text("Costs \(PetRerollPricing.cost(rerollCount: pet.rerollCount)) coins. Rerolls species and rarity.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func hatchedSection(_ pet: PetInstanceRow) -> some View {
        let xpRequired = max(1, viewModel.data?.xpRequired ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            Text("Current stage: \(pet.evolutionStage.capitalized)")
                .font(.subheadline)

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

            if let energy = viewModel.data?.energy {
                energyAndShortcuts(energy)
            }

            if let stats = viewModel.data?.stats {
                collapsibleSection(title: "Stats", isExpanded: $statsExpanded) {
                    statsGrid(stats)
                }
            }

            collapsibleSection(title: "Arena Records", isExpanded: $recordsExpanded) {
                PetCombatRecordsSection(showsHeader: false)
            }
        }
    }

    @ViewBuilder
    private func energyAndShortcuts(_ energy: ProfileEnergy) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PetEnergyBadge(energy: energy, label: "Your energy")
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                NavigationLink {
                    MarketView()
                } label: {
                    Label("Buy food", systemImage: "cart.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.green)

                if energy.max < PetEnergyPricing.maxCapacity {
                    NavigationLink {
                        MarketView()
                    } label: {
                        Label("Expand energy", systemImage: "bolt.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: isExpanded) {
                content()
                    .padding(.top, 8)
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(.accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
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

    private func titleForStage(_ stage: String) -> String {
        switch stage.lowercased() {
        case "egg": return "Your Egg"
        case "baby": return "Your Baby Pet"
        case "kid": return "Your Kid Pet"
        case "teen": return "Your Teen Pet"
        case "adult": return "Your Adult Pet"
        case "elder": return "Your Elder Pet"
        default: return "Your Pet"
        }
    }
}
