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
            answer = "Liftr is an app to log your strength, cardio and sport workouts, track your progress, compare your sessions and see what your friends are doing. Each workout generates points based on its difficulty and intensity, and your activity also earns Liftr Coins you can spend on your own virtual pet.",
            category = "General"
        ),
        FaqItem(
            question = "What are the main sections of the app?",
            answer = "There are 5 tabs: Home, Search, Add Workout, Nutrition and Profile. Home shows your feed and summaries, Search helps you discover users, Add Workout is for creating or planning sessions, Nutrition tracks your food and meal plans, and Profile includes your calendar, PRs, progress, pet and settings. Rankings open from the trophy button on your Profile.",
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
            answer = "Yes. Exercises in the same superserie appear together on one card (like Hyrox zones), with a single action to move through each exercise in the round. Rest runs after the full superserie round, not between exercises in the group.",
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
            answer = "Common reasons: unsupported activity type, date outside your selected range, a duplicate workout already imported, or missing read permissions in Health Connect. If you already logged the same session in Liftr, import may merge Health Connect data into that workout instead of creating a second one.",
            category = "Health Connect Import (Cardio)"
        ),
        FaqItem(
            question = "What can I do in Ranking?",
            answer = "You can compare performance globally or with friends, across periods and workout kinds, and switch metrics such as score, calories, level and top workouts. There are also Liftr Coins and pet leaderboards, including pet level, stats, battles and win rate.",
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
            question = "Can I bet Liftr Coins on competitions?",
            answer = "Yes. When creating a 1v1 challenge you can add an optional coin stake, limited by both players' balances. The winner takes double the stake, a draw refunds both players, and declined, cancelled or expired challenges refund the creator. Staked invites expire after 7 days if not accepted.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "Why do Calendar and Progress show different workout counts?",
            answer = "The Calendar heatmap includes days when you logged a workout as the owner and days when you only joined someone else’s session as a participant. The Progress tab only aggregates workouts you own (same rule as your published volume), excludes planned drafts, and uses rolling windows: Week is the last 7 days, Month is the last 30 days, and Year is the last 12 calendar months—so it may not match the natural month shown in Calendar.",
            category = "Goals, Ranking & Competitions"
        ),
        FaqItem(
            question = "What are Liftr Coins?",
            answer = "Liftr Coins are the in-app virtual currency. They have no real-money value and cannot be purchased or cashed out. Your balance appears in the coin badge on your Profile, and coins are mainly spent on your pet.",
            category = "Liftr Coins"
        ),
        FaqItem(
            question = "How do I earn coins?",
            answer = "Publishing workouts earns coins, with bigger rewards for longer or harder sessions. You also earn coins for liking (+2), commenting (+5), following someone (+5), gaining a follower (+10), unlocking achievements (+25 to +100 by tier), completing all weekly goals in a week (+40) and a 7-day workout streak (+50). Your pet generates coins every hour, and you can win more in pet battles and competition bets. Each like, comment or follow rewards coins only once per item.",
            category = "Liftr Coins"
        ),
        FaqItem(
            question = "Do I lose coins if I unlike or unfollow?",
            answer = "No. Coins already earned are never taken back. However, liking, commenting or following the same item or person again does not pay a second time.",
            category = "Liftr Coins"
        ),
        FaqItem(
            question = "Where can I see my coin history?",
            answer = "Tap the coin badge on your Profile to open your transaction history. You can clear the history list at any time without affecting your balance, and compare your total coins with others in the Liftr Coins ranking.",
            category = "Liftr Coins"
        ),
        FaqItem(
            question = "What can I spend coins on?",
            answer = "Coins are spent in the Pet Market (eggs, incubators and pet food), on egg rerolls, on pet rarity and energy capacity upgrades, and as optional stakes in 1v1 competitions.",
            category = "Liftr Coins"
        ),
        FaqItem(
            question = "How do I get a pet?",
            answer = "Buy a Mysterious Egg (2,000 coins) and an Egg Incubator (2,000 coins) in the Pet Market, then start incubation from My Items. The egg hatches automatically after roughly 6 to 16 hours with a random species and rarity. You can have one active pet at a time.",
            category = "Pets"
        ),
        FaqItem(
            question = "Can I reroll my egg?",
            answer = "Yes. While the egg has not hatched, you can reroll its species, rarity and hatch time for coins. The first reroll costs 50 coins and the price increases with each reroll.",
            category = "Pets"
        ),
        FaqItem(
            question = "How do pets grow and evolve?",
            answer = "Feed your pet from the Pet Market food range to gain experience; food matched to its current life stage gives the most XP. Level-ups grant stat points, and at levels 25, 50, 75 and 100 you can evolve through baby, kid, teen, adult and elder stages. The maximum level is 200.",
            category = "Pets"
        ),
        FaqItem(
            question = "What are pet rarities?",
            answer = "Pets roll a rarity when incubation starts, from Common up to Mythic. Higher rarities boost stat gains and hourly coin generation. You can upgrade rarity one tier at a time with coins, starting at 1,000 and doubling with each tier.",
            category = "Pets"
        ),
        FaqItem(
            question = "Do pets earn coins for me?",
            answer = "Yes. Hatched pets generate coins every hour based on their life stage and rarity; more evolved and rarer pets earn more. Eggs do not generate coins, and offline generation is capped at 24 hours of backlog.",
            category = "Pets"
        ),
        FaqItem(
            question = "How does the Pet Combat Arena work?",
            answer = "You can challenge another user's pet from their profile. Each challenge costs 1 energy: you have 5 energy by default, regenerate 1 every 4 hours, and can upgrade capacity up to 15 with coins. After challenging someone there is a 24-hour cooldown against the same opponent. Winners earn XP and coins based on the pets' levels, and draws give both sides a small reward.",
            category = "Pets"
        ),
        FaqItem(
            question = "Are there pet rankings?",
            answer = "Yes. Pet leaderboards let you compare pets by level, total and individual stats, battles fought, wins and win rate.",
            category = "Pets"
        ),
        FaqItem(
            question = "What can I do in the Nutrition tab?",
            answer = "You can log meals in your food diary, create and manage your own recipes and ingredients, get smart recommendations based on your metabolism, and review highlights, insights and per-category nutrition rankings.",
            category = "Nutrition"
        ),
        FaqItem(
            question = "Can I plan meals with other people?",
            answer = "Yes. You can plan meals for yourself or for other users, who receive an invite they can accept or decline, with per-person quantities. The log cart lets you add multiple ingredients and recipes in one flow before saving them to the diary or a meal plan.",
            category = "Nutrition"
        ),
        FaqItem(
            question = "Can I scan nutrition labels?",
            answer = "Yes. When adding an ingredient, you can scan a product's nutrition label with the camera and Liftr prefills the nutritional values for you to review and save.",
            category = "Nutrition"
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
        "Liftr Coins",
        "Pets",
        "Nutrition",
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
