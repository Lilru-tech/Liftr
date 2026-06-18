package com.lilru.liftr.externalroute

object ExternalRouteSourceBundles {
    const val GARMIN = "com.garmin.connect.mobile"
    const val FITBIT = "com.fitbit.FitbitMobile"
    const val POLAR = "fi.polar.polarflow"

    fun preferredBundles(provider: String): List<String> = when (provider.lowercase()) {
        "garmin" -> listOf(GARMIN)
        "fitbit" -> listOf(FITBIT)
        "polar" -> listOf(POLAR)
        else -> listOf(GARMIN, FITBIT, POLAR)
    }
}
