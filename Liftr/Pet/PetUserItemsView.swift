import SwiftUI

struct PetUserItemsView: View {
    @State private var petData: PetFullData?
    @State private var catalog: [PetMarketItemRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: PetInventoryDisplayItem?
    @State private var incubateError: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        ZStack {
            if isLoading && petData == nil {
                ProgressView("Loading your items...")
                    .padding()
            } else if let errorMessage, displayItems.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding()
            } else if displayItems.isEmpty {
                Text("You don't own any pet items yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedItems, id: \.0) { category, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(PetMarketVisibility.categoryTitle(category))
                                    .font(.title3.weight(.semibold))
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(items) { item in
                                        PetInventoryItemCard(item: item) {
                                            withAnimation { selectedItem = item }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }

            if let selectedItem {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { self.selectedItem = nil }
                    }

                PetInventoryItemOverlay(
                    item: selectedItem,
                    hasIncubator: PetMarketVisibility.hasIncubator(petData?.inventory ?? []),
                    canIncubate: PetMarketVisibility.canIncubate(petData: petData),
                    onClose: {
                        withAnimation { self.selectedItem = nil }
                    },
                    onIncubate: {
                        await startIncubation()
                    }
                )
                .transition(.scale)
            }
        }
        .navigationTitle("My Items")
        .gradientBG()
        .task { await reload() }
        .alert("Error", isPresented: Binding(
            get: { incubateError != nil },
            set: { if !$0 { incubateError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(incubateError ?? "")
        }
    }

    private var displayItems: [PetInventoryDisplayItem] {
        (petData?.inventory ?? []).compactMap { PetInventoryDisplayItem.from(inventory: $0, catalog: catalog) }
    }

    private var groupedItems: [(String, [PetInventoryDisplayItem])] {
        let dict = Dictionary(grouping: displayItems, by: \.category)
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    private func reload() async {
        isLoading = petData == nil
        errorMessage = nil
        do {
            async let market = PetService.shared.fetchMarketItems()
            async let pet = PetService.shared.fetchMyPet()
            catalog = try await market
            petData = try await pet
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startIncubation() async {
        do {
            let hatchAt = try await PetService.shared.startIncubation()
            await reload()
            if let hatchAt, let petType = petData?.pet?.petType {
                PetHatchLocalNotificationScheduler.schedule(hatchAt: hatchAt, petType: petType)
            }
            withAnimation { selectedItem = nil }
        } catch {
            incubateError = error.localizedDescription
        }
    }
}
