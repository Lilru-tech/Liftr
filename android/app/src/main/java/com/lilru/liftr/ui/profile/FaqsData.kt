package com.lilru.liftr.ui.profile

data class FaqItem(
    val question: String,
    val answer: String,
    val category: String
)

object FaqsData {
    /**
     * Paridad con [Liftr.FAQsView] (iOS); en Android “Health Connect” sustituye a Apple Health donde aplica.
     */
    val items: List<FaqItem> = listOf(
        FaqItem(
            question = "What is Liftr Workout?",
            answer = "Liftr is an app to log your strength, cardio and sport workouts, track your progress, compare your sessions and see what your friends are doing. Each workout generates points based on its difficulty and intensity.",
            category = "General"
        ),
        FaqItem(
            question = "What are the main sections of the app?",
            answer = "There are 5 tabs: Home, Search, Add Workout, Ranking and Profile. Home shows your feed and summaries, Search helps you discover users, Add Workout is for creating or planning sessions, Ranking compares stats, and Profile includes your calendar, PRs, progress and settings.",
            category = "General"
        ),
        FaqItem(
            question = "Can I create workouts now and also plan them for later?",
            answer = "Yes. In Add Workout you can publish a completed workout or save it as planned (draft) and start it later from workout details.",
            category = "General"
        ),
        FaqItem(
            question = "Where can I find routines and workout suggestions?",
            answer = "When creating a strength workout, you can load routines and use suggested sessions based on your training history.",
            category = "General"
        ),
        FaqItem(
            question = "What can I edit while a strength workout is active?",
            answer = "During the active strength flow, you can edit reps, weight and rest for the current set configuration, add sets, remove sets, move to the next exercise, or finish early.",
            category = "Active Strength Workout"
        ),
        FaqItem(
            question = "How does rest work in active strength workouts?",
            answer = "If a set has rest seconds configured, the app starts a rest timer after you tap the rest button. You can skip rest any time. The top stopwatch shows elapsed session time.",
            category = "Active Strength Workout"
        ),
        FaqItem(
            question = "When are active strength changes saved?",
            answer = "The workout is persisted when you finish the session. If you finish early, only the sets you actually performed are saved.",
            category = "Active Strength Workout"
        ),
        FaqItem(
            question = "Can I run supersets in the active strength view?",
            answer = "There is no dedicated superset mode in this flow. Work is tracked exercise by exercise with per-set reps, weight and rest.",
            category = "Active Strength Workout"
        ),
        FaqItem(
            question = "What is dual/group strength on one phone?",
            answer = "From a planned strength workout, you can start just yourself, dual (you + 1 partner), or group (you + 2 partners) on the same device.",
            category = "Group Workouts"
        ),
        FaqItem(
            question = "Do all participants keep separate results in dual/group mode?",
            answer = "Yes. Each lane keeps its own reps, weights and rest timers while sharing the same screen for navigation.",
            category = "Group Workouts"
        ),
        FaqItem(
            question = "What happens if not everyone is done and we tap Finish?",
            answer = "You will see a warning and can cancel or finish for everyone. Finishing closes and saves all linked workouts running on that phone.",
            category = "Group Workouts"
        ),
        FaqItem(
            question = "What does Liftr import from Health Connect?",
            answer = "Only compatible cardio workouts: running, walking, hiking, cycling, swimming and rowing. Indoor runs and walks can map to treadmill or similar activities when supported.",
            category = "Health Connect Import (Cardio)"
        ),
        FaqItem(
            question = "Does Liftr write back to Health Connect?",
            answer = "No. This integration is read-only for import. Liftr does not write, edit or delete workouts in Health Connect from this import flow.",
            category = "Health Connect Import (Cardio)"
        ),
        FaqItem(
            question = "Is Health Connect import automatic?",
            answer = "No. Import is manual: choose a date range in settings and start the import from compatible sessions.",
            category = "Health Connect Import (Cardio)"
        ),
        FaqItem(
            question = "Why was a Health Connect workout not imported?",
            answer = "Common reasons: unsupported activity type, date outside your selected range, a duplicate workout already imported, or missing read permissions in Health Connect.",
            category = "Health Connect Import (Cardio)"
        ),
        FaqItem(
            question = "What can I do in Ranking?",
            answer = "You can compare performance globally or with friends, across periods and workout kinds, and switch metrics such as score, calories, level and top workouts.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "How do weekly goals work?",
            answer = "You can set weekly goals for workouts, calories or score and track progress through the week. Suggested targets are based on your recent history.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "What are competitions in Liftr?",
            answer = "Competitions let you challenge others with defined rules and review participating workouts in dedicated competition screens.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "Why do Calendar and Progress show different workout counts?",
            answer = "The Calendar heatmap includes days when you logged a workout as the owner and days when you only joined someone else’s session as a participant. The Progress tab only aggregates workouts you own (same rule as your published volume), excludes planned drafts, and uses rolling windows: Week is the last 7 days, Month is the last 30 days, and Year is the last 12 calendar months—so it may not match the natural month shown in Calendar.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "What can I manage in Profile settings?",
            answer = "You can update personal info, contact support, open FAQs, import cardio from Health Connect, restore purchases, sign out, or permanently delete your account.",
            category = "Privacy, Account & Support"
        ),
        FaqItem(
            question = "Can I delete my account?",
            answer = "Yes. Account deletion is available in Profile settings and removes your account data according to app policy.",
            category = "Privacy, Account & Support"
        ),
        FaqItem(
            question = "How do I ask for help or suggest features?",
            answer = "Use Contact Support for issues and the Feature Requests section to propose product ideas directly in the app.",
            category = "Privacy, Account & Support"
        ),
        FaqItem(
            question = "How are workout points calculated?",
            answer = "Score depends on your profile factors and workout data. Strength uses volume, reps and sets; cardio uses distance, pace and time; sport uses match stats. More demanding sessions earn more points.",
            category = "Premium & Ads"
        ),
        FaqItem(
            question = "What are Premium benefits?",
            answer = "Premium removes ads in the app. It is billed monthly via Google Play and can be restored from Settings.",
            category = "Premium & Ads"
        )
    )

    private val sectionOrder: List<String> = listOf(
        "General",
        "Active Strength Workout",
        "Group Workouts",
        "Health Connect Import (Cardio)",
        "Goals, Ranking & Competitions",
        "Privacy, Account & Support",
        "Premium & Ads"
    )

    val orderedSections: List<Pair<String, List<FaqItem>>>
        get() {
            val by = items.groupBy { it.category }
            val preferred = sectionOrder.filter { by.containsKey(it) }
            val rest = (by.keys - preferred.toSet()).toList().sorted()
            return (preferred + rest).map { section -> section to (by[section] ?: emptyList()) }
        }
}
