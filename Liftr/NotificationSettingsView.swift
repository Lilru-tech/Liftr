import SwiftUI
import Supabase

struct NotificationSettingsRow: Codable {
    let userId: UUID
    var pushEnabled: Bool
    var pushNewMessage: Bool
    var pushNewFollower: Bool
    var pushWorkoutLike: Bool
    var pushWorkoutComment: Bool
    var pushCommentLike: Bool
    var pushCommentReply: Bool
    var pushCommentMention: Bool
    var pushAddedAsParticipant: Bool
    var pushAchievementUnlocked: Bool
    var pushGoalCompleted: Bool
    var pushGoalAlmostDone: Bool
    var pushCompetitionInvite: Bool
    var pushCompetitionAccepted: Bool
    var pushCompetitionDeclined: Bool
    var pushCompetitionCancelled: Bool
    var pushCompetitionExpired: Bool
    var pushCompetitionResultWin: Bool
    var pushCompetitionResultLose: Bool
    var pushCompetitionWorkoutPendingReview: Bool
    var pushCompetitionWorkoutAccepted: Bool
    var pushCompetitionWorkoutRejected: Bool
    var pushSegmentYouAreFirst: Bool
    var pushSegmentLostFirst: Bool
    var pushTerritoryCaptureFromUser: Bool
    var pushTerritoryLostToUser: Bool
    var pushChallengeWon: Bool
    var pushChallengeWonWeekly: Bool
    var pushWorkoutKindInactive: Bool
    var pushAppleHealthCardioImported: Bool
    var appleHealthCardioPushKnownOnServer: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pushEnabled = "push_enabled"
        case pushNewMessage = "push_new_message"
        case pushNewFollower = "push_new_follower"
        case pushWorkoutLike = "push_workout_like"
        case pushWorkoutComment = "push_workout_comment"
        case pushCommentLike = "push_comment_like"
        case pushCommentReply = "push_comment_reply"
        case pushCommentMention = "push_comment_mention"
        case pushAddedAsParticipant = "push_added_as_participant"
        case pushAchievementUnlocked = "push_achievement_unlocked"
        case pushGoalCompleted = "push_goal_completed"
        case pushGoalAlmostDone = "push_goal_almost_done"
        case pushCompetitionInvite = "push_competition_invite"
        case pushCompetitionAccepted = "push_competition_accepted"
        case pushCompetitionDeclined = "push_competition_declined"
        case pushCompetitionCancelled = "push_competition_cancelled"
        case pushCompetitionExpired = "push_competition_expired"
        case pushCompetitionResultWin = "push_competition_result_win"
        case pushCompetitionResultLose = "push_competition_result_lose"
        case pushCompetitionWorkoutPendingReview = "push_competition_workout_pending_review"
        case pushCompetitionWorkoutAccepted = "push_competition_workout_accepted"
        case pushCompetitionWorkoutRejected = "push_competition_workout_rejected"
        case pushSegmentYouAreFirst = "push_segment_you_are_first"
        case pushSegmentLostFirst = "push_segment_lost_first"
        case pushTerritoryCaptureFromUser = "push_territory_capture_from_user"
        case pushTerritoryLostToUser = "push_territory_lost_to_user"
        case pushChallengeWon = "push_challenge_won"
        case pushChallengeWonWeekly = "push_challenge_won_weekly"
        case pushWorkoutKindInactive = "push_workout_kind_inactive"
        case pushAppleHealthCardioImported = "push_apple_health_cardio_imported"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        pushEnabled = try c.decode(Bool.self, forKey: .pushEnabled)
        pushNewMessage = try c.decode(Bool.self, forKey: .pushNewMessage)
        pushNewFollower = try c.decode(Bool.self, forKey: .pushNewFollower)
        pushWorkoutLike = try c.decode(Bool.self, forKey: .pushWorkoutLike)
        pushWorkoutComment = try c.decode(Bool.self, forKey: .pushWorkoutComment)
        pushCommentLike = try c.decode(Bool.self, forKey: .pushCommentLike)
        pushCommentReply = try c.decode(Bool.self, forKey: .pushCommentReply)
        pushCommentMention = try c.decodeIfPresent(Bool.self, forKey: .pushCommentMention) ?? true
        pushAddedAsParticipant = try c.decode(Bool.self, forKey: .pushAddedAsParticipant)
        pushAchievementUnlocked = try c.decode(Bool.self, forKey: .pushAchievementUnlocked)
        pushGoalCompleted = try c.decode(Bool.self, forKey: .pushGoalCompleted)
        pushGoalAlmostDone = try c.decode(Bool.self, forKey: .pushGoalAlmostDone)
        pushCompetitionInvite = try c.decode(Bool.self, forKey: .pushCompetitionInvite)
        pushCompetitionAccepted = try c.decode(Bool.self, forKey: .pushCompetitionAccepted)
        pushCompetitionDeclined = try c.decode(Bool.self, forKey: .pushCompetitionDeclined)
        pushCompetitionCancelled = try c.decode(Bool.self, forKey: .pushCompetitionCancelled)
        pushCompetitionExpired = try c.decode(Bool.self, forKey: .pushCompetitionExpired)
        pushCompetitionResultWin = try c.decode(Bool.self, forKey: .pushCompetitionResultWin)
        pushCompetitionResultLose = try c.decode(Bool.self, forKey: .pushCompetitionResultLose)
        pushCompetitionWorkoutPendingReview = try c.decode(Bool.self, forKey: .pushCompetitionWorkoutPendingReview)
        pushCompetitionWorkoutAccepted = try c.decode(Bool.self, forKey: .pushCompetitionWorkoutAccepted)
        pushCompetitionWorkoutRejected = try c.decode(Bool.self, forKey: .pushCompetitionWorkoutRejected)
        pushSegmentYouAreFirst = try c.decode(Bool.self, forKey: .pushSegmentYouAreFirst)
        pushSegmentLostFirst = try c.decode(Bool.self, forKey: .pushSegmentLostFirst)
        pushTerritoryCaptureFromUser = try c.decode(Bool.self, forKey: .pushTerritoryCaptureFromUser)
        pushTerritoryLostToUser = try c.decode(Bool.self, forKey: .pushTerritoryLostToUser)
        pushChallengeWon = try c.decode(Bool.self, forKey: .pushChallengeWon)
        pushChallengeWonWeekly = try c.decode(Bool.self, forKey: .pushChallengeWonWeekly)
        pushWorkoutKindInactive = try c.decode(Bool.self, forKey: .pushWorkoutKindInactive)
        appleHealthCardioPushKnownOnServer = c.contains(.pushAppleHealthCardioImported)
        pushAppleHealthCardioImported = try c.decodeIfPresent(Bool.self, forKey: .pushAppleHealthCardioImported) ?? true
    }
}

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var row: NotificationSettingsRow?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?

    private var pushMaster: Bool {
        row?.pushEnabled ?? true
    }

    var body: some View {
        List {
            if loading {
                Section {
                    ProgressView("Loading…")
                }
            } else if let error {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn’t load settings")
                            .font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if row != nil {
                Section {
                    toggleCard(
                        title: "Push notifications",
                        isOn: binding(\.pushEnabled),
                        enabled: !saving
                    )
                } footer: {
                    Text("These toggles control whether Liftr sends push notifications to your phone. Notifications can still appear inside the app.")
                }

                Section("Messages") {
                    toggleCard(
                        title: "Direct messages",
                        isOn: binding(\.pushNewMessage),
                        enabled: pushMaster && !saving
                    )
                }

                Section("Social") {
                    toggleCard(
                        title: "New followers",
                        isOn: binding(\.pushNewFollower),
                        enabled: pushMaster && !saving
                    )
                }

                Section("Workouts") {
                    toggleCard(title: "Workout likes", isOn: binding(\.pushWorkoutLike), enabled: pushMaster && !saving)
                    toggleCard(title: "Workout comments", isOn: binding(\.pushWorkoutComment), enabled: pushMaster && !saving)
                    toggleCard(title: "Comment likes", isOn: binding(\.pushCommentLike), enabled: pushMaster && !saving)
                    toggleCard(title: "Comment replies", isOn: binding(\.pushCommentReply), enabled: pushMaster && !saving)
                    toggleCard(title: "Comment mentions", isOn: binding(\.pushCommentMention), enabled: pushMaster && !saving)
                    toggleCard(title: "Added as participant", isOn: binding(\.pushAddedAsParticipant), enabled: pushMaster && !saving)
                }

                Section("Achievements & Goals") {
                    toggleCard(title: "Achievements", isOn: binding(\.pushAchievementUnlocked), enabled: pushMaster && !saving)
                    toggleCard(title: "Goal completed", isOn: binding(\.pushGoalCompleted), enabled: pushMaster && !saving)
                    toggleCard(title: "Goal almost done", isOn: binding(\.pushGoalAlmostDone), enabled: pushMaster && !saving)
                }

                Section("Competitions") {
                    toggleCard(title: "Invites", isOn: binding(\.pushCompetitionInvite), enabled: pushMaster && !saving)
                    toggleCard(title: "Accepted", isOn: binding(\.pushCompetitionAccepted), enabled: pushMaster && !saving)
                    toggleCard(title: "Declined", isOn: binding(\.pushCompetitionDeclined), enabled: pushMaster && !saving)
                    toggleCard(title: "Cancelled", isOn: binding(\.pushCompetitionCancelled), enabled: pushMaster && !saving)
                    toggleCard(title: "Expired", isOn: binding(\.pushCompetitionExpired), enabled: pushMaster && !saving)
                    toggleCard(title: "Result: win", isOn: binding(\.pushCompetitionResultWin), enabled: pushMaster && !saving)
                    toggleCard(title: "Result: lose", isOn: binding(\.pushCompetitionResultLose), enabled: pushMaster && !saving)
                    toggleCard(title: "Workout pending review", isOn: binding(\.pushCompetitionWorkoutPendingReview), enabled: pushMaster && !saving)
                    toggleCard(title: "Workout accepted", isOn: binding(\.pushCompetitionWorkoutAccepted), enabled: pushMaster && !saving)
                    toggleCard(title: "Workout rejected", isOn: binding(\.pushCompetitionWorkoutRejected), enabled: pushMaster && !saving)
                }

                Section("Segments & Challenges") {
                    toggleCard(title: "Segment: you are first", isOn: binding(\.pushSegmentYouAreFirst), enabled: pushMaster && !saving)
                    toggleCard(title: "Segment: lost first", isOn: binding(\.pushSegmentLostFirst), enabled: pushMaster && !saving)
                    toggleCard(title: "Territory captured from others", isOn: binding(\.pushTerritoryCaptureFromUser), enabled: pushMaster && !saving)
                    toggleCard(title: "Territory lost to others", isOn: binding(\.pushTerritoryLostToUser), enabled: pushMaster && !saving)
                    toggleCard(title: "Challenge won", isOn: binding(\.pushChallengeWon), enabled: pushMaster && !saving)
                    toggleCard(title: "Challenge won (weekly)", isOn: binding(\.pushChallengeWonWeekly), enabled: pushMaster && !saving)
                }

                Section("Reminders") {
                    toggleCard(title: "Workout reminders", isOn: binding(\.pushWorkoutKindInactive), enabled: pushMaster && !saving)
                }

                Section("Apple Health") {
                    toggleCard(
                        title: "Cardio workout imported",
                        isOn: binding(\.pushAppleHealthCardioImported),
                        enabled: pushMaster && !saving
                    )
                }
            }
        }
        .navigationTitle("Notifications")
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .gradientBG()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if saving {
                    ProgressView()
                }
            }
        }
        .task {
            if row == nil && !loading {
                await load()
            }
        }
        .refreshable {
            await load()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationSettingsRow, Bool>) -> Binding<Bool> {
        Binding(
            get: { row?[keyPath: keyPath] ?? true },
            set: { newValue in
                guard row != nil else { return }
                row?[keyPath: keyPath] = newValue
                Task { await save() }
            }
        )
    }

    private func toggleCard(title: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18))
                )

            Toggle(title, isOn: isOn)
                .disabled(!enabled)
                .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func load() async {
        let client = SupabaseManager.shared.client
        guard let user = client.auth.currentUser else {
            await MainActor.run { error = "Not signed in."; row = nil; loading = false }
            return
        }

        await MainActor.run { loading = true; error = nil }
        defer { Task { @MainActor in loading = false } }

        do {
            let res = try await client
                .from("user_notification_settings")
                .select("*")
                .eq("user_id", value: user.id)
                .limit(1)
                .execute()

            let rows = try JSONDecoder.supabase().decode([NotificationSettingsRow].self, from: res.data)

            if let first = rows.first {
                await MainActor.run { row = first }
                return
            }

            _ = try await client
                .from("user_notification_settings")
                .insert(["user_id": user.id.uuidString])
                .execute()

            let res2 = try await client
                .from("user_notification_settings")
                .select("*")
                .eq("user_id", value: user.id)
                .limit(1)
                .execute()

            let rows2 = try JSONDecoder.supabase().decode([NotificationSettingsRow].self, from: res2.data)
            await MainActor.run { row = rows2.first }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard let row else { return }
        let client = SupabaseManager.shared.client

        await MainActor.run { saving = true; error = nil }
        defer { Task { @MainActor in saving = false } }

        struct UpdatePayload: Encodable {
            let push_enabled: Bool
            let push_new_message: Bool
            let push_new_follower: Bool
            let push_workout_like: Bool
            let push_workout_comment: Bool
            let push_comment_like: Bool
            let push_comment_reply: Bool
            let push_comment_mention: Bool
            let push_added_as_participant: Bool
            let push_achievement_unlocked: Bool
            let push_goal_completed: Bool
            let push_goal_almost_done: Bool
            let push_competition_invite: Bool
            let push_competition_accepted: Bool
            let push_competition_declined: Bool
            let push_competition_cancelled: Bool
            let push_competition_expired: Bool
            let push_competition_result_win: Bool
            let push_competition_result_lose: Bool
            let push_competition_workout_pending_review: Bool
            let push_competition_workout_accepted: Bool
            let push_competition_workout_rejected: Bool
            let push_segment_you_are_first: Bool
            let push_segment_lost_first: Bool
            let push_territory_capture_from_user: Bool
            let push_territory_lost_to_user: Bool
            let push_challenge_won: Bool
            let push_challenge_won_weekly: Bool
            let push_workout_kind_inactive: Bool
            let push_apple_health_cardio_imported: Bool?

            enum CodingKeys: String, CodingKey {
                case push_enabled
                case push_new_message
                case push_new_follower
                case push_workout_like
                case push_workout_comment
                case push_comment_like
                case push_comment_reply
                case push_comment_mention
                case push_added_as_participant
                case push_achievement_unlocked
                case push_goal_completed
                case push_goal_almost_done
                case push_competition_invite
                case push_competition_accepted
                case push_competition_declined
                case push_competition_cancelled
                case push_competition_expired
                case push_competition_result_win
                case push_competition_result_lose
                case push_competition_workout_pending_review
                case push_competition_workout_accepted
                case push_competition_workout_rejected
                case push_segment_you_are_first
                case push_segment_lost_first
                case push_territory_capture_from_user
                case push_territory_lost_to_user
                case push_challenge_won
                case push_challenge_won_weekly
                case push_workout_kind_inactive
                case push_apple_health_cardio_imported
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(push_enabled, forKey: .push_enabled)
                try c.encode(push_new_message, forKey: .push_new_message)
                try c.encode(push_new_follower, forKey: .push_new_follower)
                try c.encode(push_workout_like, forKey: .push_workout_like)
                try c.encode(push_workout_comment, forKey: .push_workout_comment)
                try c.encode(push_comment_like, forKey: .push_comment_like)
                try c.encode(push_comment_reply, forKey: .push_comment_reply)
                try c.encode(push_comment_mention, forKey: .push_comment_mention)
                try c.encode(push_added_as_participant, forKey: .push_added_as_participant)
                try c.encode(push_achievement_unlocked, forKey: .push_achievement_unlocked)
                try c.encode(push_goal_completed, forKey: .push_goal_completed)
                try c.encode(push_goal_almost_done, forKey: .push_goal_almost_done)
                try c.encode(push_competition_invite, forKey: .push_competition_invite)
                try c.encode(push_competition_accepted, forKey: .push_competition_accepted)
                try c.encode(push_competition_declined, forKey: .push_competition_declined)
                try c.encode(push_competition_cancelled, forKey: .push_competition_cancelled)
                try c.encode(push_competition_expired, forKey: .push_competition_expired)
                try c.encode(push_competition_result_win, forKey: .push_competition_result_win)
                try c.encode(push_competition_result_lose, forKey: .push_competition_result_lose)
                try c.encode(push_competition_workout_pending_review, forKey: .push_competition_workout_pending_review)
                try c.encode(push_competition_workout_accepted, forKey: .push_competition_workout_accepted)
                try c.encode(push_competition_workout_rejected, forKey: .push_competition_workout_rejected)
                try c.encode(push_segment_you_are_first, forKey: .push_segment_you_are_first)
                try c.encode(push_segment_lost_first, forKey: .push_segment_lost_first)
                try c.encode(push_territory_capture_from_user, forKey: .push_territory_capture_from_user)
                try c.encode(push_territory_lost_to_user, forKey: .push_territory_lost_to_user)
                try c.encode(push_challenge_won, forKey: .push_challenge_won)
                try c.encode(push_challenge_won_weekly, forKey: .push_challenge_won_weekly)
                try c.encode(push_workout_kind_inactive, forKey: .push_workout_kind_inactive)
                try c.encodeIfPresent(push_apple_health_cardio_imported, forKey: .push_apple_health_cardio_imported)
            }
        }

        let payload = UpdatePayload(
            push_enabled: row.pushEnabled,
            push_new_message: row.pushNewMessage,
            push_new_follower: row.pushNewFollower,
            push_workout_like: row.pushWorkoutLike,
            push_workout_comment: row.pushWorkoutComment,
            push_comment_like: row.pushCommentLike,
            push_comment_reply: row.pushCommentReply,
            push_comment_mention: row.pushCommentMention,
            push_added_as_participant: row.pushAddedAsParticipant,
            push_achievement_unlocked: row.pushAchievementUnlocked,
            push_goal_completed: row.pushGoalCompleted,
            push_goal_almost_done: row.pushGoalAlmostDone,
            push_competition_invite: row.pushCompetitionInvite,
            push_competition_accepted: row.pushCompetitionAccepted,
            push_competition_declined: row.pushCompetitionDeclined,
            push_competition_cancelled: row.pushCompetitionCancelled,
            push_competition_expired: row.pushCompetitionExpired,
            push_competition_result_win: row.pushCompetitionResultWin,
            push_competition_result_lose: row.pushCompetitionResultLose,
            push_competition_workout_pending_review: row.pushCompetitionWorkoutPendingReview,
            push_competition_workout_accepted: row.pushCompetitionWorkoutAccepted,
            push_competition_workout_rejected: row.pushCompetitionWorkoutRejected,
            push_segment_you_are_first: row.pushSegmentYouAreFirst,
            push_segment_lost_first: row.pushSegmentLostFirst,
            push_territory_capture_from_user: row.pushTerritoryCaptureFromUser,
            push_territory_lost_to_user: row.pushTerritoryLostToUser,
            push_challenge_won: row.pushChallengeWon,
            push_challenge_won_weekly: row.pushChallengeWonWeekly,
            push_workout_kind_inactive: row.pushWorkoutKindInactive,
            push_apple_health_cardio_imported: row.appleHealthCardioPushKnownOnServer
                ? row.pushAppleHealthCardioImported
                : nil
        )

        do {
            _ = try await client
                .from("user_notification_settings")
                .update(payload)
                .eq("user_id", value: row.userId.uuidString)
                .execute()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

