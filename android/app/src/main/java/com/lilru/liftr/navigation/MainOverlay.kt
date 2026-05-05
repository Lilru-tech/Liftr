package com.lilru.liftr.navigation

import java.util.UUID

/**
 * Pantallas full-screen encima del shell (paridad con hojas de [Liftr/RootView.swift]).
 */
sealed class MainOverlay {
    data class WorkoutDetail(val workoutId: Int, val ownerId: String?) : MainOverlay()
    data class SegmentDetail(val segmentId: UUID) : MainOverlay()
    data class FollowerProfile(val userId: String) : MainOverlay()
    data class Goals(val userId: String) : MainOverlay()
    data class Achievements(val fromNotification: Boolean = false) : MainOverlay()
    data object CompetitionsHub : MainOverlay()
    data class CompetitionDetailById(val competitionId: Int) : MainOverlay()
    data object CompetitionReviews : MainOverlay()
    data class AddWorkoutDraftKind(val kind: String) : MainOverlay()
}
