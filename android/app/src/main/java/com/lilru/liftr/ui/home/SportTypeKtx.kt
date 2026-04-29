package com.lilru.liftr.ui.home

import com.lilru.liftr.ui.add.AddSportType

/** Resuelve el [AddSportType] a partir de la columna [sport_sessions.sport]. */
fun addSportTypeFromWire(w: String): AddSportType? =
    AddSportType.entries.find { it.wire == w.trim().lowercase() }
