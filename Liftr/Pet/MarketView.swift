import SwiftUI

struct MarketView: View {
    @ObservedObject private var coinManager = CoinManager.shared
    @State private var items: [PetMarketItemRow] = []
    @State private var petData: PetFullData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: PetMarketItemRow?

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
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .navigationTitle("Market")
        .gradientBG()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PetUserItemsView()
                        .gradientBG()
                } label: {
                    Image(systemName: "bag.fill")
                        .font(.title3)
                }
            }
        }
        .task {
            await coinManager.refreshBalance()
            await reload()
        }
    }

    private var coinBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bitcoinsign.circle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            Text("\(coinManager.balance) coins")
                .font(.headline.weight(.bold))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
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
