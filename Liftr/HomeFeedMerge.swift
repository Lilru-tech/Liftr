import Foundation

struct HomeFeedMerge {
    static func merge<Item>(
        existing: [Item],
        incoming: [Item],
        id: (Item) -> Int,
        startedAt: (Item) -> Date?
    ) -> [Item] {
        var byId: [Int: Item] = [:]

        for item in existing {
            byId[id(item)] = item
        }

        for item in incoming {
            byId[id(item)] = item
        }

        return byId.values.sorted {
            let leftDate = startedAt($0) ?? .distantPast
            let rightDate = startedAt($1) ?? .distantPast

            if leftDate == rightDate {
                return id($0) > id($1)
            }

            return leftDate > rightDate
        }
    }

    static func shouldApplyResult(currentGeneration: UUID, resultGeneration: UUID) -> Bool {
        currentGeneration == resultGeneration
    }
}
