import SwiftUI

struct PetHelpSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Pet information")
                        .font(.title2.weight(.semibold))

                    hatchingSection
                    foodSection
                    tipsSection
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
    }

    @ViewBuilder
    private var hatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to hatch an egg")
                .font(.headline)

            numberedStep(1, "Buy a Mysterious Egg and an Egg Incubator in the Market.")
            myItemsStep
            numberedStep(3, "Tap your egg and choose Incubate. You need an Egg Incubator in your inventory.")

            Text("Your egg hatches automatically in about 6 to 16 hours. You can have one active pet at a time.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var myItemsStep: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("2.")
                .font(.body.weight(.semibold))
                .frame(width: 20, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Open My Items using the")
                Image(systemName: "bag.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("icon in the Market toolbar.")
            }
            .font(.body)
        }
    }

    @ViewBuilder
    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.body)
        }
    }

    @ViewBuilder
    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pet food")
                .font(.headline)
                .padding(.top, 6)

            Text("Each life stage has matching food. Using the correct food gives the most experience.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                foodRow(stage: "Baby", food: "Baby Snack")
                foodRow(stage: "Kid", food: "Kid Cookies")
                foodRow(stage: "Teen", food: "Teen Treat")
                foodRow(stage: "Adult", food: "Adult Biscuit")
                foodRow(stage: "Elder", food: "Elder Delight")
            }

            Text("Buy food in the Market, then feed your pet from its detail screen.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func foodRow(stage: String, food: String) -> some View {
        Text("\(stage) — \(food)")
            .font(.body)
    }

    @ViewBuilder
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good to know")
                .font(.headline)
                .padding(.top, 6)

            tipRow(
                title: "Reroll",
                body: "While incubating, before hatch, you can reroll species, rarity, and hatch time for coins."
            )
            tipRow(
                title: "Rarities",
                body: "Open Pet Dex from your Profile menu (⋯) for drop rates, multipliers, and upgrade costs."
            )
            tipRow(
                title: "Evolution",
                body: "Pets evolve at levels 25, 50, 75, and 100 through baby, kid, teen, adult, and elder stages."
            )
        }
    }

    @ViewBuilder
    private func tipRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
