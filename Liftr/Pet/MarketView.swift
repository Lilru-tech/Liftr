import SwiftUI

struct MarketView: View {
    @ObservedObject private var coinManager = CoinManager.shared
    @ObservedObject private var purchaseFeedback = PetMarketPurchaseFeedback.shared
    @State private var items: [PetMarketItemRow] = []
    @State private var petData: PetFullData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: PetMarketItemRow?
    @State private var showPetHelp = false

    var body: some View {
        ZStack {
            if isLoading && items.isEmpty {
                PetMarketSkeletonView()
                    .transition(.opacity)
            } else if let errorMessage, items.isEmpty {
                ScrollView {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        coinBanner

                        ForEach(groupedCategories, id: \.0) { category, categoryItems in
                            categorySection(category: category, items: categoryItems)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }

            if let selectedItem {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { self.selectedItem = nil }
                    }

                Group {
                    if selectedItem.itemType == "pet_rarity_upgrade" {
                        RarityUpgradeDetailOverlay(
                            item: selectedItem,
                            petData: petData,
                            userCoins: coinManager.balance,
                            onClose: {
                                withAnimation { self.selectedItem = nil }
                            },
                            onPurchaseSuccess: {
                                withAnimation { self.selectedItem = nil }
                                Task { await reload() }
                            }
                        )
                    } else if selectedItem.itemType == "pet_energy_capacity" {
                        EnergyCapacityUpgradeOverlay(
                            item: selectedItem,
                            petData: petData,
                            userCoins: coinManager.balance,
                            onClose: {
                                withAnimation { self.selectedItem = nil }
                            },
                            onPurchaseSuccess: {
                                withAnimation { self.selectedItem = nil }
                                Task { await reload() }
                            }
                        )
                    } else {
                        MarketItemDetailOverlay(
                            item: selectedItem,
                            userCoins: coinManager.balance,
                            onClose: {
                                withAnimation { self.selectedItem = nil }
                            },
                            onPurchaseSuccess: {
                                withAnimation { self.selectedItem = nil }
                                Task { await reload() }
                            }
                        )
                    }
                }
                .transition(.scale)
                .zIndex(2)
            }

            if let message = purchaseFeedback.toastMessage {
                VStack {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    Spacer()
                }
                .zIndex(3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.25), value: purchaseFeedback.toastMessage)
        .navigationTitle("Market")
        .gradientBG()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showPetHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Pet information")

                    if purchaseFeedback.unseenMyItemsCount > 0 {
                        NavigationLink {
                            PetUserItemsView()
                                .gradientBG()
                        } label: {
                            Image(systemName: "bag.fill")
                                .font(.title3)
                        }
                        .badge(purchaseFeedback.unseenMyItemsCount)
                    } else {
                        NavigationLink {
                            PetUserItemsView()
                                .gradientBG()
                        } label: {
                            Image(systemName: "bag.fill")
                                .font(.title3)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPetHelp) {
            PetHelpSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
        }
        .task {
            await coinManager.refreshBalance()
            await reload()
        }
    }

    private var coinBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)
                Text("\(coinManager.balance) coins")
                    .font(.headline.weight(.bold))
                Spacer()
                if let energy = petData?.energy {
                    PetEnergyBadge(energy: energy, alignment: .trailing)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityIdentifier("market.coinBanner")
    }

    @ViewBuilder
    private func categorySection(category: String, items: [PetMarketItemRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PetMarketVisibility.categoryTitle(category))
                .font(.title2.weight(.bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        let presentation = PetMarketItemPresentation.make(item: item, petData: petData)
                        PetMarketItemCard(
                            item: item,
                            userCoins: coinManager.balance,
                            effectivePrice: presentation.effectivePrice,
                            subtitle: presentation.subtitle,
                            imagePath: presentation.imagePath
                        ) {
                            withAnimation { selectedItem = item }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var groupedCategories: [(String, [PetMarketItemRow])] {
        let visible = items.filter { PetMarketVisibility.shouldShowMarketItem($0, petData: petData) }
        let dict = Dictionary(grouping: visible, by: \.category)
        return dict.keys.sorted().compactMap { key in
            let categoryItems = dict[key] ?? []
            return categoryItems.isEmpty ? nil : (key, categoryItems)
        }
    }

    private func reload() async {
        isLoading = items.isEmpty
        errorMessage = nil
        do {
            async let market = PetService.shared.fetchMarketItems()
            async let pet = PetService.shared.fetchMyPet()
            items = try await market
            petData = try await pet
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
