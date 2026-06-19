package com.lilru.liftr.externalroute

object ExternalRouteDedupPolicy {
    const val LIFTR_ROUTE_PROVIDER_KEY = "com.lilru.liftr.external_route_provider"
    const val LIFTR_ROUTE_ID_KEY = "com.lilru.liftr.external_route_id"
    const val LIFTR_HAS_CUSTOM_ROUTE_KEY = "com.lilru.liftr.has_custom_route"

    fun routeMetadata(provider: String, providerActivityId: String): Map<String, String> =
        mapOf(
            LIFTR_HAS_CUSTOM_ROUTE_KEY to "true",
            LIFTR_ROUTE_PROVIDER_KEY to provider,
            LIFTR_ROUTE_ID_KEY to providerActivityId
        )
}
