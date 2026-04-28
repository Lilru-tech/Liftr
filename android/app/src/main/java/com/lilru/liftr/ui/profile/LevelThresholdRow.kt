package com.lilru.liftr.ui.profile

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Fila de [BackendContracts.Tables.LEVEL_THRESHOLDS]; compartida por [ProfileViewModel] y [UserLevelDetailViewModel]. */
@Serializable
internal data class LevelThresholdRow(
    val level: Int,
    @SerialName("xp_required") val xpRequired: Long
)
