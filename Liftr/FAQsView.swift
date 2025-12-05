import SwiftUI

struct FAQsView: View {
    private struct FAQ: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
        let category: String
    }

    private var faqsBySection: [String: [FAQ]] {
        let faqs: [FAQ] = [
            FAQ(
                question: "What is Liftr Workout?",
                answer: "Liftr is an app to log your strength, cardio and sport workouts, track your progress, compare your sessions and see what your friends are doing. Each workout generates points based on its difficulty and intensity.",
                category: "General"
            ),
            FAQ(
                question: "What are the main sections of the app?",
                answer: "There are 5 tabs: Home (your workouts and the workouts of people you follow), Search (find users and view their profiles), Add Workout (create or schedule a session), Ranking (see who is on top by different metrics) and Profile (view and edit your profile, PRs, progress and settings).",
                category: "General"
            ),

            FAQ(
                question: "What can I see on the Home screen?",
                answer: "On Home you see your workouts and the workouts of people you follow. You can filter by All, Strength, Cardio or Sport. At the top you’ll find cards for: today’s workouts, your current streak (plus how many workouts you’ve done this week and total points), your strongest week by points and your highest-scoring workout. There’s also a monthly card with number of workouts, total points, percentage vs last month, plus a chart you can share.",
                category: "Home"
            ),
            FAQ(
                question: "What information appears in each workout card?",
                answer: "Each card shows: profile photo, username, workout title, date, category (Strength, Cardio or Sport), points earned and number of likes. Tapping the card opens the full workout details.",
                category: "Home"
            ),

            FAQ(
                question: "What can I do from the workout detail screen?",
                answer: "If the workout is yours you can edit it, duplicate it, delete it and compare it with other workouts of the same type. You’ll always see the full details, the likes (with the list of who liked it) and the comments.",
                category: "Workouts"
            ),
            FAQ(
                question: "What is a Draft workout and what does the Start button do?",
                answer: "If you create a workout as a Draft (planned), a Start button will appear. Tapping it opens the active workout view, where you can see remaining time, sets and reps (Strength), goals, cards and assists or other stats (Sport), or distance and pace (Cardio). From this view you can fill in the data while you train.",
                category: "Workouts"
            ),

            FAQ(
                question: "How do I add or schedule a workout?",
                answer: "In the Add Workout tab you choose: workout type (Strength, Cardio or Sport), mode (add now or schedule), title, start date and time, whether it has finished, end date and time, notes and intensity. Then you can add participants (people you follow) and fill in the specific fields for that type of workout: total volume, sets and reps in Strength; pace, distance and other data in Cardio; or match stats such as goals, cards and assists in Sport.",
                category: "Add workouts"
            ),
            FAQ(
                question: "Where do the workouts I add appear?",
                answer: "All workouts you create appear on Home and also in your profile, whether they are past sessions or scheduled ones.",
                category: "Add workouts"
            ),

            FAQ(
                question: "What is the Search tab for?",
                answer: "Search lets you find other users by name and open their profiles. From there you can see their workouts, PRs and progress, and decide if you want to follow them.",
                category: "Search & ranking"
            ),
            FAQ(
                question: "What does the Ranking tab show?",
                answer: "Ranking shows who has the most workouts, the most points and other stats among your friends or globally. There are filters so you can choose which type of ranking you want to see.",
                category: "Search & ranking"
            ),

            FAQ(
                question: "What can I see and change in my profile?",
                answer: "In Profile you see your photo (tap it to change it), your username, followers and following (each with its own list), your level and XP, and your bio (editable). You also have shortcuts to the Ranking, your notifications and your unlocked achievements.",
                category: "Profile"
            ),
            FAQ(
                question: "What do the Calendar, PRs and Progress tabs show inside Profile?",
                answer: "Calendar shows the current month: days with completed workouts are highlighted in green and days with planned workouts (Drafts) in maroon. PRs shows your personal records for different exercises and sports. Progress shows your evolution by number of workouts and score, for different time ranges (week, month, year).",
                category: "Profile"
            ),
            FAQ(
                question: "What options are available in Settings inside Profile?",
                answer: "In Settings you can become Premium to remove ads, change the app background color, contact support, update your personal info (height, weight, date of birth), delete your account or sign out.",
                category: "Profile"
            ),

            FAQ(
                question: "How are workout points calculated?",
                answer: "Your score depends on several factors: your weight, age and sex, the type of workout and its specific data. In Strength we look at total volume lifted, sets and reps; in Cardio, pace, distance and time; and in Sport, match stats like goals, cards, assists and more. The harder and more demanding the session, the more points you earn.",
                category: "Scoring & Premium"
            ),
            FAQ(
                question: "What are the benefits of being a Premium user?",
                answer: "With a Premium subscription you remove ads from the app. The subscription is monthly and is managed through your Apple account. You can restore purchases from Settings if you change devices.",
                category: "Scoring & Premium"
            )
        ]

        return Dictionary(grouping: faqs, by: { $0.category })
    }

    var body: some View {
        List {
            ForEach(faqsBySection.keys.sorted(), id: \.self) { section in
                if let items = faqsBySection[section] {
                    Section(section) {
                        ForEach(items) { faq in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(faq.question)
                                    .font(.subheadline.weight(.semibold))
                                Text(faq.answer)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.18))
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .background(Color.clear)
        .navigationTitle("FAQs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
