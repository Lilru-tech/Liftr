import Foundation
import HealthKit

enum ExternalRouteDedupPolicy {
    static let liftrRouteProviderKey = "com.lilru.liftr.external_route_provider"
    static let liftrRouteIdKey = "com.lilru.liftr.external_route_id"
    static let liftrHasCustomRouteKey = "com.lilru.liftr.has_custom_route"

    static func shouldSkip(
        workout: HKWorkout,
        existingRoutes: [HKWorkoutRoute],
        provider: String,
        providerActivityId: String
    ) -> Bool {
        if existingRoutes.contains(where: { route in
            (route.metadata?[liftrRouteIdKey] as? String) == providerActivityId
        }) {
            return true
        }
        if workout.metadata?[liftrHasCustomRouteKey] as? Bool == true {
            return true
        }
        if !existingRoutes.isEmpty {
            return true
        }
        return false
    }

    static func routeMetadata(provider: String, providerActivityId: String) -> [String: Any] {
        [
            liftrHasCustomRouteKey: true,
            liftrRouteProviderKey: provider,
            liftrRouteIdKey: providerActivityId,
        ]
    }
}
