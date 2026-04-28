package com.lilru.liftr.ui.profile

data class FaqItem(
    val question: String,
    val answer: String,
    val category: String
)

object FaqsData {
    val items: List<FaqItem> = listOf(
        FaqItem(
            question = "What is Liftr Workout?",
            answer = "Liftr is an app to log your strength, cardio and sport workouts, track your progress, compare your sessions and see what your friends are doing. Each workout generates points based on its difficulty and intensity.",
            category = "General"
        ),
        FaqItem(
            question = "What are the main sections of the app?",
            answer = "There are 5 tabs: Home (your workouts and the workouts of people you follow), Search (find users and view their profiles), Add Workout (create or schedule a session), Ranking (see who is on top by different metrics) and Profile (view and edit your profile, PRs, progress and settings).",
            category = "General"
        ),
        FaqItem(
            question = "What can I see on the Home screen?",
            answer = "On Home you see your workouts and the workouts of people you follow. You can filter by All, Strength, Cardio or Sport. At the top you will find cards for: today's workouts, your current streak (plus how many workouts you have done this week and total points), your strongest week by points and your highest-scoring workout. There is also a monthly card with number of workouts, total points, percentage vs last month, plus a chart you can share.",
            category = "Home"
        ),
        FaqItem(
            question = "What information appears in each workout card?",
            answer = "Each card shows: profile photo, username, workout title, date, category (Strength, Cardio or Sport), points earned and number of likes. Tapping the card opens the full workout details.",
            category = "Home"
        ),
        FaqItem(
            question = "What can I do from the workout detail screen?",
            answer = "If the workout is yours you can edit it, duplicate it, delete it and compare it with other workouts of the same type. You will always see the full details, the likes (with the list of who liked it) and the comments.",
            category = "Workouts"
        ),
        FaqItem(
            question = "What is a Draft workout and what does the Start button do?",
            answer = "If you create a workout as a Draft (planned), a Start button will appear. Tapping it opens the active workout view, where you can see remaining time, sets and reps (Strength), goals, cards and assists or other stats (Sport), or distance and pace (Cardio). From this view you can fill in the data while you train.",
            category = "Workouts"
        ),
        FaqItem(
            question = "How do I add or schedule a workout?",
            answer = "In the Add Workout tab you choose: workout type (Strength, Cardio or Sport), mode (add now or schedule), title, start date and time, whether it has finished, end date and time, notes and intensity. Then you can add participants (people you follow) and fill in the specific fields for that type of workout: total volume, sets and reps in Strength; pace, distance and other data in Cardio; or match stats such as goals, cards and assists in Sport.",
            category = "Add workouts"
        ),
        FaqItem(
            question = "Where do the workouts I add appear?",
            answer = "All workouts you create appear on Home and also in your profile, whether they are past sessions or scheduled ones.",
            category = "Add workouts"
        ),
        FaqItem(
            question = "What is the Search tab for?",
            answer = "Search lets you find other users by name and open their profiles. From there you can see their workouts, PRs and progress, and decide if you want to follow them.",
            category = "Search & ranking"
        ),
        FaqItem(
            question = "What does the Ranking tab show?",
            answer = "Ranking shows who has the most workouts, the most points and other stats among your friends or globally. There are filters so you can choose which type of ranking you want to see.",
            category = "Search & ranking"
        ),
        FaqItem(
            question = "What can I see and change in my profile?",
            answer = "In Profile you see your photo (tap to change it), your username, followers and following (each with its own list), your level and XP, and your bio (editable on your own profile). You have a Calendar card for the month, shortcuts to PRs, Progress, Goals, Achievements, competitions, and more, plus notifications and other actions when it is your profile.",
            category = "Profile"
        ),
        FaqItem(
            question = "What do the Calendar, PRs and Progress sections show in Profile?",
            answer = "Calendar shows the current month: your own completed workouts are highlighted in green, days where you only participated in someone else’s session in yellow, and planned (scheduled) sessions in maroon. Tap a day to list that day’s workouts. PRs shows your personal records. Progress shows charts (workouts, score, calories, intensity, consistency) for week, month or year.",
            category = "Profile"
        ),
        FaqItem(
            question = "What options are available on my own profile (account and settings)?",
            answer = "You can become Premium to remove ads, change the app background color, import sessions from Health Connect (Android) or Health (iOS), contact support, open FAQs and feature requests, update your personal info (height, weight, date of birth), delete your account or sign out. Exact layout follows each platform, but the features match.",
            category = "Profile"
        ),
        FaqItem(
            question = "How are workout points calculated?",
            answer = "Your score depends on several factors: your weight, age and sex, the type of workout and its specific data. In Strength we look at total volume lifted, sets and reps; in Cardio, pace, distance and time; and in Sport, match stats like goals, cards, assists and more. The harder and more demanding the session, the more points you earn.",
            category = "Scoring & Premium"
        ),
        FaqItem(
            question = "What are the benefits of being a Premium user?",
            answer = "With a Premium subscription you remove ads from the app. The subscription is monthly and is billed through the App Store on iOS or Google Play on Android. You can restore purchases from Settings if you change devices.",
            category = "Scoring & Premium"
        )
    )

    val sections: List<Pair<String, List<FaqItem>>>
        get() = items
            .groupBy { it.category }
            .toList()
            .sortedBy { it.first }
            .map { (cat, list) -> cat to list }
}
