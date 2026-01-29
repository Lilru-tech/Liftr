# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-01-29

### Added
- **User Competitions (1v1)**
  - Users can **invite other users** to a 1 vs 1 competition.
  - Invitations create a competition in **pending** state with:
    - Selected **goal type** and target value
    - **Start date** (set on accept)
    - **Invitation expiration** (e.g., 48h) → auto-moves to **expired** if not answered
  - The sender can **cancel** an invitation any time before it’s accepted.
  - Anti-spam safeguards:
    - Limit on **maximum pending invitations** per user (e.g., 5)
    - Users can **block** others from sending future competition invites
  - Invited users can:
    - **Accept** → competition becomes **active** immediately
    - **Decline** → competition moves to **declined**
  - Competition goals:
    - Allowed setups:
      - **Time limit only**
      - **One performance goal only**: Calories / Score / Workouts
      - **Time limit + one performance goal**
    - Not allowed: **multiple performance goals** in the same competition (e.g., calories + score)
    - Competition ends when:
      - The **time limit** is reached, or
      - The **performance goal** is reached
    - If both users reach the performance goal **on the same day**, the result is a **draw**

### Changed
- **Profile quick actions**
  - Hidden **Notifications**, **Goals**, and **Competitions** icons from the profile header and moved them into a **three-dots (⋯) menu**.

- **Active Strength Workout UI**
  - Improved focus by making non-current exercise cards **more blurred**.
  - Rest timer is no longer visible on **other exercises**.
  - Improved tap behavior so the **full button area** is interactive.

### Fixed
- **Search results styling**
  - Fixed the **background color** for results in the search view.

- **Calories calculation**
  - Fixed an issue that caused calories to be slightly **overestimated**.

[1.3.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.3.0

## [1.2.0] - 2026-01-27

### Added
- **Goals (Weekly + All-time)**
  - Users can now create **weekly goals** (Workouts / Calories / Score).
  - Goals include a **weekly view** to track progress in real time and an **all-time history** to review past goals.
  - Added an all-time summary to visualize total goals, finished goals, average progress and best performance.

- **Calories tracking**
  - Workouts now store and display **calories burned** when a workout is completed.
  - Added **Calories** to the **Profile → Progress** section.
  - Added **Score summary** in **Profile → Progress** for a clearer overview of performance.

- **Ranking: Calories**
  - Added a new leaderboard metric based on **Calories**.

### Changed
- **Active Strength Workout UX**
  - Users can now move between exercises while an active strength workout is running.
  - Strength workouts can now be **finished even if not all planned sets are completed**.
  - Rest timer is now visible after finishing an exercise.
  - Users can **add/remove sets at any moment**, including during the workout flow.

### Fixed
- **Achievements deep-link from push notifications**
  - Fixed a layout issue when opening **Achievements** from a push notification.
  - Added clear UI indicators to dismiss/close the view.

- **Strength workout creation blocked**
  - Fixed a bug where users couldn’t add a strength workout unless the “finished hour” was provided.
  - Strength workouts can now be created with correct validation and without forcing end-time input.

[1.2.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.2.0

## [1.1.2] - 2026-01-22

### Added
- **User functionality suggestions**
  - Added a new suggestions list to track and prioritize user-requested improvements.

- **New exercises**
  - Expanded the exercise catalog with new entries.

### Fixed
- **Notifications view**
  - Fixed layout/behavior issues in the notifications screen.

- **Strength workouts publishing without title**
  - Fixed a bug where workouts could not be published when the Title field was empty (Title is now optional).
  
[1.1.2]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.1.2

## [1.1.1] - 2025-12-15

### Added
- **Marketing URL in the App Store Connect**

[1.1.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.1.1

## [1.1.0] - 2025-12-05

### Added
- **Banner ads on main screens**
  - Added banner ads to the **Home**, **Search**, **Ranking**, and **Profile** tabs.

- **Premium (ad-free) mode**
  - New in-app **Premium** option that removes banner ads across the app once purchased or restored.
  - Premium state is persisted locally so the app remains ad-free on subsequent launches.

- **Ranking → Top workouts metric**
  - Added a new **“Top workouts”** metric to `RankingView` that shows the best individual workouts ordered by score.
  - Fully compatible with existing filters: **Scope** (Global/Friends), **Period**, **Type** (Strength/Cardio/Sport), **Sex**, and **Age band**.

- **Profile → Settings → FAQs**
  - Added an **FAQ** section under profile settings with common questions and answers about using Liftr, scoring, and privacy.

- **Profile → Themes**
  - New **Themes** section in profile settings that lets you change the **app background gradient / theme color**.
  - The selected theme is stored per user and applied across all main screens.

- **Push notifications**
  - Added push notifications for:
    - New **comments** on your workouts.
    - **Likes** on workouts.
    - **Likes** on comments.
    - **Replies** to your comments.
    - New **followers**.
    - When someone **adds you as a participant** in a workout.
    - Newly unlocked **achievements**.

### Changed
- **Workout comments UX**
  - Moved the comment input field from the **top** of the thread to the **bottom**, closer to the latest messages.
  - Fixed background color inconsistencies in the comments view to better match the rest of the app.
  - Tapping on a commenter’s avatar or username now navigates directly to their **profile**.

[1.1.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.1.0

## [1.0.1] - 2025-12-02

### Added
- **Profile → Contact support**
  - New in-app contact form under **Profile → Settings → Support**, with subject picker and message field.
  - Messages are stored in the `contact_messages` table so support can be handled from your backend/DB instead of via Mail.

- **Profile calendar → Draft workouts highlight**
  - Days that contain only **draft workouts** are now highlighted in a muted **burgundy/red** color to distinguish them from published sessions.

- **ActiveWorkout for draft sessions**
  - You can now start a workout directly from a draft using the new **ActiveWorkout** flow, turning planned sessions into live workouts.

- **Profile workout cards → Avatars**
  - Workout cards in the profile now show the **profile image of the current user** and of other users who have added you as a participant, when available.

- **Workout deletion**
  - Added the ability to **delete workouts** from the profile/detail flow, with proper UI refresh and data sync.

- **Extra sport-specific fields**
  - Added more specific fields for **Hyrox, Handball, Hockey and Rugby**, both in the workout forms and in the stored session data.

- **Richer comparisons for Sports & Strength**
  - Strength and Sport comparison views now include additional metrics, making it easier to understand how two sessions differ.

### Changed
- **Home → Empty state**
  - When there are no workout data for the user, the **summary / today points / insights** cards are hidden so the Home screen doesn’t feel empty or broken.

### Fixed
- **Strength workouts without notes**
  - Fixed a bug where **Strength** workouts could not be saved if the **Notes** field was empty. Notes are now fully optional again.

[1.0.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.0.1
[Released]: https://github.com/Lilru-tech/Liftr/compare/v1.0.1...HEAD

## [1.0.0] - 2025-11-12

### Added
- **Account deletion (end-to-end)**
  - New DB function: `public.delete_user_cascade(p_user uuid)` and wrapper RPC `public.delete_my_account()`.
  - New Edge Function: `delete-auth-user` (service role) to remove the Supabase **Auth** user.
  - App flow (Profile → Settings → Delete account) now calls the Edge Function and falls back to the RPC, ensuring both **public** data and **auth** identity are deleted.
  - Idempotent behavior: safe if the user or related rows were already removed.

### Changed
- **Workout comparison (v1.1)**
  - When the viewer has **multiple eligible workouts**, a **selector sheet** is shown to pick which one to compare.
  - Sorted by **date (newest first)** with clear labels; if there’s only one candidate, it’s auto-selected as before.

### Fixed
- Minor SwiftUI styling mismatch in destructive button foreground style (consistency across iOS versions).

### Database
- Functions:
  - `delete_user_cascade(uuid)` — `SECURITY DEFINER`; `GRANT EXECUTE TO anon, authenticated, service_role`.
  - `delete_my_account()` — `SECURITY DEFINER`; `GRANT EXECUTE TO authenticated, service_role`.
- No RLS changes; deletion runs server-side under controlled privileges.

### Ops
- Deployed Edge Function `delete-auth-user`.
- Project secrets configured for the function: `SERVICE_ROLE_KEY`, `PROJECT_URL` (no `SUPABASE_` prefix).

[1.0.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v1.0.0
[Released]: https://github.com/Lilru-tech/Liftr/compare/v1.0.0...HEAD

## [0.9.5] - 2025-11-11

### Added
- **Workout comparison (v1)**
  - New sheet from `WorkoutDetailView` to compare **His/Her (red)** vs **Yours (green)**.
  - Contextual header “His/Her vs Yours — {Kind}”.
  - Metrics by type:
    - **Strength**: *Total volume (kg)*, *Exercises*, *Sets*.
    - **Cardio**: distance, duration, avg pace, avg/max HR, elevation; optional extras when present (cadence, watts, incline, swim laps, pool length, split/500m).
    - **Sport**: duration, score for/against + sport-specific KPIs (racket, basketball, football, volleyball).
  - Row shows **% difference badge** and **polished bars** (translucent track + gradient capsules with subtle shadow).
  - Empty state and loading via `ProgressView`.
- **Ranking → Profile navigation**
  - Tapping a row in **RankingView** now opens the selected user’s **Profile** (deep-link aware; preserves existing filters on back).
- **Profile photo preview**
  - Tap the avatar to open a **full-screen preview** of the profile photo (dismiss with tap or swipe).

### Changed
- **Sheet presentation**
  - `.presentationDetents([.fraction(0.88), .large])`, `.presentationDragIndicator(.visible)`, and `gradientBG()` for a tighter, polished look.
  - Persistent **Close** (✕) button on the top-left.
  - Workout IDs are hidden; shows **His/Her** and **Yours** labels with colors instead.
  - Metric cards: increased inner padding, rounded corners, subtle stroke, and clipping to avoid any bar overflow.

### Fixed
- **Strength compare not showing** (e.g., 205 vs 148): adjusted comparison logic so Strength no longer depends on identical titles.
- **Swift 6**: local concurrent functions marked `@Sendable`; fixed static use of `prettyMetric`.
- Prevented visual **overflow** of bars beyond the card.

### Database
- **RPC `can_compare_workout_v1(p_viewer uuid, p_workout bigint)`**
  - Now allows comparing **any Strength workout** from the viewer (own or participated), without requiring the same title.
  - Keeps the existing rules for **Cardio** (same activity/modality) and **Sport** (same sport).
  - Returns `sample_viewer_match_id` plus flags `viewer_can_compare_with_owner` / `viewer_has_comparable_workout`.
  - No schema or RLS changes.

[0.9.5]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.5
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.5...HEAD

## [0.9.4] - 2025-11-07

### Added
- **Global TopBanner (reusable)**
  - Unified success/error/info banners with `BannerPresenter` + `BannerAction` (auto-hide, tap-to-dismiss, haptics).
  - Adopted across flows:
    - **Editing a workout**: after saving, show a success message (e.g., “Workout updated! 💪”).
    - **Profile → Personal information**: after saving, show **“Profile updated! ✅”** and exit edit mode.
    - **RegisterView**: migrated to the same banner system for success/errors.
- **Profile → Personal information**
  - New **edit pencil** in the top-right to toggle edit mode.
  - Users can now change **weight** and **date of birth** (age is derived).
- **PRs**
  - Added a **Search** option (toggleable search bar like in other lists).
- **Home → Workout cards**
  - Added **type icons** for **Strength / Cardio / Sport**, plus per-sport icons (e.g., padel/football/basketball/tennis/volleyball).

### Changed
- **Profile → Save changes**
  - Pressing **Save changes** now **closes edit mode** and returns to read-only view while showing a success banner.
- **Cardio & Sport forms**
  - Added/refined **specific fields** for Cardio and Sport sessions to match the latest scoring and PR/achievement definitions.
- **PRs & Achievements catalogs**
  - Reviewed and **expanded PRs** and **Achievements** to cover **sport-specific** and **cardio** metrics added recently.

### Fixed
- **Sport selector**
  - **Hyrox** was missing in the selector — now visible and selectable.
- **Notes input trimming**
  - Fixed multi-line **Notes** being visually cut off in relevant editors.
- **Achievements**
  - **Search input hidden by default**, mirroring the PRs behavior (toggleable when needed).
- **Strength points after editing**
  - Editing strength workouts now **recalculates points correctly** (no stale scores).
- **Points consistency**
  - Reviewed/tuned **Strength** scoring and **Cardio/Sport** point calculations to reflect the new specific fields and ensure consistent totals.
- **Thread-safety & warnings**
  - Removed `MainActor.run { Task { ... } }` misuse and ensured state updates on the main actor (fixes “Result of call to 'run(...)' is unused” warning).

### Database
- **No breaking changes.**
- Updated server logic to ensure **score recalculation** on **Strength** edits and to incorporate the refined **Cardio/Sport** metrics.
- Expanded PRs/Achievements sources to include the newly supported **sport-specific** and **cardio** fields.

[0.9.4]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.4
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.4...HEAD

## [0.9.3] - 2025-11-05

### Added
- **Home → Sport badge with per-sport icon**
  - Sport workouts now display a single **“Sport” pill** with a **contextual icon** (e.g., padel racket, football, basketball, tennis, volleyball).
  - Accessibility: VoiceOver announces “Sport: {sport name}”.
- **Intelligent title for Sport**
  - If a Sport workout has no custom `title`, the **sport name** is used as the card title (e.g., “Padel”, “Football”).
- **Sport-specific fields (creation & edit)**
  - The Add/Edit flow now surfaces **custom fields per sport type**:
    - **Football**: score for/against, match score text, location, duration.
    - **Basketball**: score for/against, period/quarters (text), location, duration.
    - **Volleyball**: sets won/lost, per-set score text, location, duration.
    - **Racket sports** (Padel/Tennis/Badminton): sets/games, tie-break notes, result and duration, location.
  - UI renders only the relevant inputs based on the selected sport.

### Changed
- **Sport pill design**
  - Kept a **single pill** (“Sport” + icon) to minimize visual noise and keep consistency with Strength/Cardio tints.
- **Add/Edit forms**
  - Conditional sections ensure a compact layout: generic sport fields are shown first, followed by the sport-specific block.

### Fixed
- **Home feed update path**
  - Workout update handler now preserves `likeCount` / `isLiked` and score when patching feed items, avoiding regressions during `.workoutUpdated`.

### Database
- **Schema (non-breaking extensions)**
  - Extended `public.sport_sessions` with **sport-specific columns** grouped by type (nullable; backward compatible). Examples include:
    - `football_score_for`, `football_score_against`, `basketball_period_text`,
      `volleyball_sets_won`, `volleyball_sets_lost`,
      `racket_sets_text`, `match_score_text`, `location`, `duration_sec`.
- **Functions / RPC**
  - Updated `create_sport_workout_v1(p jsonb)` to accept and persist the new **sport-specific fields** while keeping previous payloads valid.
- **Soft decay for inactivity (score pipeline)**
  - Introduced a **soft decay** that reduces awarded points when a user has been **inactive for X days**:
    - New helper: `get_inactivity_multiplier(p_user_id uuid, p_at timestamptz)` → `numeric` (e.g., `1.0` down to a configured floor).
    - The multiplier is applied when inserting into `workout_scores` (or at score aggregation), so recent consistent activity yields full points while long gaps apply a gentle reduction.
    - Parameters (threshold, slope, floor) are configurable via constants or a settings table.
  - RLS: unchanged; decay is applied server-side and respects existing visibility rules.

### Ops / Migration Notes
- Run lightweight migration adding the new nullable columns to `sport_sessions`.
- Deploy the updated `create_sport_workout_v1` and the `get_inactivity_multiplier` helper.
- No backfill required; historic scores remain intact unless you explicitly reprocess them.

[0.9.3]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.3
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.3...HEAD

## [0.9.2] - 2025-11-03

### Added
- **Level Leaderboard (v1)**
- New **metric selector** in `RankingView` (**Score · Level**).
- New `LevelRankRow` showing **rank · avatar · username · Level · XP**.
- Level leaderboard supports filters: **Scope (Global/Friends)**, **Sex**, **Age band**.  
*(Filters **Period** and **Kind** are hidden when Level is selected).*
- **RPC: `get_level_leaderboard_v1`**
- Params: `(p_scope, p_limit, p_sex, p_age_band)`
- Returns: `(rank, user_id, username, avatar_url, level, xp)`
- `SECURITY DEFINER`; `GRANT EXECUTE TO authenticated` (revoked from `public`)

### Changed
- **XP → Level pipeline (stability)**
- Ensured level init through `ensure_user_level(p_user)` (signup + backfill safe).
- Verified XP event flow: `xp_events → recalc_user_level_for(...)`.
- Deterministic ordering in leaderboard: **XP DESC**, tie-breaker by **username ASC**.
- **Ranking UI**
- Clear segmentation for metrics (Score / Level) with contextual hiding of irrelevant filters.
- Unified visual style for level rows using `SectionCard`.

### Fixed
- **Users without XP/Level**
- Users with no prior XP no longer break the leaderboard (shown as `level = 1, xp = 0` when applicable).
- **Level thresholds**
- Fixed off-by-one issue in `level_thresholds` (safe clamp to minimum level).

### Database
- **Functions:** added `get_level_leaderboard_v1` (see above).  
- **RLS:** unchanged; RPC respects existing visibility rules (`scope` + allowed joins).  
- **Recommended ops migration:**
- Backfill: run `ensure_user_level(u.user_id)` for all existing users.
- Recompute: run `recalc_all_user_levels()` to sync levels with current XP totals.

[0.9.2]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.2  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.2...HEAD

## [0.9.1] - 2025-11-02

### Added
- **PRs → Empty state**
- When there are no PRs to compare, we now show an informative message instead of leaving the view blank.
- **Exercise catalog metadata**
- Added `muscle group` and `equipment` fields to exercises (foundation for future filters and display).
- **Participants can duplicate workouts**
- Users listed as participants can now **Duplicate** a workout from `WorkoutDetailView` (opens **Add** with a pre-filled draft).

### Changed
- **Unified gray cards (visual polish)**
- Applied the same soft gray “card/pill” style across:
- **Profile → PRs** rows
- **Profile → Settings** fields
- **ExercisePickerSheet** input fields
- **EditWorkoutMetaSheet** (participants block + fields)
- Consistent rounded corners and subtle white stroke for all cards.
- **PRs section headers behavior**
- Unpinned section headers (**Cardio / Strength / Sport**) to avoid overlapping while scrolling.
- **Auto duration**
- When both **Started at** and **Ended at** are set, **Duration** is now calculated automatically for **Cardio** and **Sport** sessions.

### Fixed
- **Custom exercise name**
- Custom names are correctly saved and displayed in `WorkoutDetailView`.
- **Home → Workout Card participants**
- Cards now show **more than one participant** reliably.
- **Color inconsistencies**
- Corrected background and field colors in the sheets listed above to match the new gray theme.

[0.9.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.1
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.1...HEAD

## [0.9.0] - 2025-10-30
### Added
- **Workout Participants (v1)**
- Now you can **add users as participants** when creating or editing a workout.
- Participants are shown in the **WorkoutDetailView**.
- **Calendar highlights**:
- **Green** for your own workouts.
- **Yellow** for workouts where you participated in someone else’s session.
- **Day list** groups “Participated” sessions under a dedicated label.

### Changed
- **AddWorkoutSheet / EditWorkoutMetaSheet**
- Integrated participant picker and persistence when saving or duplicating workouts.
- **ProfileView → Calendar**
- Merged own + participated activity to compute daily highlights and counts correctly.

### Database
- **Tables:** Uses existing `workout_participants` linkage.
- **RLS:** Read policies confirmed so participants can view the workouts they joined.
- **Functions:** No changes; handled via Supabase client inserts.

[0.9.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.9.0
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.9.0...HEAD

## [0.8.0] - 2025-10-29  
### Added  
- **Achievements System (v1)**  
- Implemented a complete **achievement framework** integrated with both frontend and database.  
- Achievements now automatically unlock when users meet specific milestones (e.g., workout count, distance, strength, comments, likes, followers).  
- Introduced **AchievementsGridView** for a clean, visual representation of all unlocked and locked achievements.  
- Each achievement displays its icon, progress state, and tooltip with description.  
- Added **meta-achievements** (e.g., unlock 10, 25, 50 achievements).  
- Backend function `check_and_unlock_achievements_for(user_id)` now manages unlocking logic across social, cardio, strength, and comment/like events.  

- **PR Comparison (v1)**  
- Added **Personal Record comparison between users**, allowing athletes to see how their best lifts and times compare to other users in the community.  
- Comparison highlights **differences in top strength and cardio records**, showing where each user excels.  
- Accessible directly from **ProfileView → PRs tab**, with a clean comparative layout and stat highlighting.  

### Changed  
- **Profile → Achievements section**  
- Replaced static placeholder grid with fully functional `AchievementsGridView`.  
- Locked achievements now appear semi-transparent with tooltips explaining unlock criteria.  
- Layout optimized for both small and large device screens (dynamic grid columns).  

### Database  
- **Functions:**  
- Added `check_and_unlock_achievements_for(p_user_id uuid)` with complete logic for all achievement types.  
- Updated triggers to call this function automatically when relevant user actions occur (follow, like, comment, workout creation).  
- **Tables:**  
- Added/updated `achievements` and `user_achievements` with all predefined milestone entries.  
- **RLS:**  
- Confirmed secure visibility for achievements per authenticated user.  

[0.8.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.8.0  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.8.0...HEAD  

## [0.7.1] - 2025-10-28  
### Added  
- **Workout Planner (v1)**  
- Introduced the **Plan mode** in the Add Workout screen, allowing users to schedule workouts ahead of time.  
- Planned workouts appear in Home as **“Draft”** until published.  
- Added **state transitions** (`planned → published`) with proper UI refresh and Realtime sync.  

- **New Exercises are highlighted**  
- When adding a new exercise, it is hightlighet to give more visibility

- **Delete Exercises confirmation modal**  
- When deleting an exercise, a modal to confirm appears. This is due to avoid missclicks in the delete exercise option

### Changed  
- **Logo update**  
- Replaced the previous app logo and icon with a refreshed, modernized version.  

- **Profile navigation flow**  
- Improved user profile routing from Home, Ranking, and Search tabs.  
- Added deep-link consistency to ensure profile reloads only when necessary.  

- **Like button UX**  
- Adjusted tap area and gesture priority so that tapping the heart no longer opens the likes list.  
- Improved responsiveness and feedback animation when liking a workout.  

### Fixed  
- **Shared card visibility**  
- Fixed an issue where shared workout cards were sometimes invisible to followers due to missing RLS propagation.  
- Updated visibility checks to include shared workouts in the public feed.  

### Database  
- **Functions:**  
- Rebuilt `create_cardio_workout(...)` and `create_strength_workout(...)` to support planned/published states.  
- **Tables:**  
- `workouts.state` now limited to `('planned', 'published', 'archived')`.  
- No structural changes to other tables.  
- **RLS:**  
- Verified visibility propagation for shared workouts and planner-created entries.  

[0.7.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.7.1  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.7.1...HEAD  

## [0.7.0] - 2025-10-27
### Added
- **WorkoutDetailView → Comments (v1.1)**
- **Reply UX**: inline “Reply” composer under each comment/reply.
- **Thread toggling**: “View X replies” now switches to **“Hide replies”** when expanded.
- **Comment likes**: heart toggle with live counter on both **top-level** comments and **replies** (optimistic UI).

### Changed
- **Replies loader**  
- `loadReplies(for:forceReload:)` added; used after posting a reply to **refresh the thread without a full screen reload**.
- When replying to a collapsed thread, the parent now **auto-expands** before reload.
- **Like updates**  
- Optimistic updates for `likesCount` and `likedByMe` on target comment/reply, with backend **fallback sync** via `reloadSingle` on error.

### Fixed
- **Replies not appearing until manual refresh**: after posting a reply, the parent thread is **force-reloaded** and shown immediately.
- **“View X replies” label** didn’t change to **“Hide replies”** when expanded — now toggles correctly.
- **Soft-delete feedback**: deleted comments now **update instantly** in place and show a neutral **“Comment deleted”** placeholder.

### Database
- **No schema changes.**
- Reads/Writes:
- `workout_comments` (insert replies, soft-delete with `deleted_at`, `deleted_by`)
- `workout_comment_likes` (insert/delete)
- `profiles` (display info)
- **RLS unchanged.**

[0.7.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.7.0  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.7.0...HEAD

## [0.6.7] - 2025-10-27
### Added
- **Home → Likes on workout cards**
- Added a **like pill** on each feed card with a **heart icon** (filled if liked by the user) and **counter**.
- Reuses `workout_likes` to fetch both total likes and whether the current user has liked (`isLiked`).
- Batched loading: during pagination, `workout_likes` are queried with `IN (workout_id)` and merged into in-memory results.
- **Home → Insights (v1)**
- Introduced new **insight pills** displayed in the feed:
- `💪 Strongest week this month: {points} points`
- `⚽ Best sport match: {score} ({sport})`
- Data sources reused:
- **Streak**: consecutive training days (last 60 days).
- **Strongest week (MTD)**: total `workout_scores` grouped by week of the current month.
- **Best sport match**: highest `score` from `sport` workouts (via `sport_sessions` for sport name).

### Changed
- **Feed item model**  
- `FeedItem` now includes `likeCount: Int` and `isLiked: Bool`.
- `HomeFeedCard` updated to render the **like pill** next to the **score pill**.
- **Home feed loading (pagination & refresh)**  
- `loadPage(...)` and `refreshOne(...)` now also retrieve and attach `likeCount` / `isLiked` along with `score`.

### Fixed
- **Compile error (“type-check in reasonable time”)**  
- Fixed by **building `FeedItem` with all required fields** (`likeCount` and `isLiked`) in the `.workoutUpdated` notification handler.  
- Prevents heavy type inference in the closure and stabilizes compilation time.

### Database
- **No schema changes.**  
- Reads from `workout_likes`, `workout_scores`, `sport_sessions`, and `workouts`. Existing RLS policies remain valid.

[0.6.7]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.7  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.7...HEAD

## [0.6.6] - 2025-10-26
### Added
- **Home → Monthly Summary (v1, collapsible)**
- Added a new **“{Month} {Year} summary”** card displaying key monthly metrics.
- Includes a **Show more / Show less** toggle to expand or collapse the chart area.
- Added a **Share your progress** button (using `ImageRenderer`) that exports the summary as an image.
- Displays contextual **medal/star badge** when workout or improvement thresholds are reached.

### Changed
- **Month-to-Date logic & copy**
- Monthly summary now reflects **Month-To-Date (MTD)** data — from the 1st of the current month up to the current day.
- Improvement percentage is calculated against the **previous full month**.
- Texts localized to English: **“Workouts / Total score / Improvement”**.
- **Home layout**
- The monthly summary card is now rendered **inside the feed list**, not above it — freeing vertical space.
- Default state is **collapsed**, allowing the feed to remain the main focus.
- Unified chart style (soft gray background, rounded corners, Catmull-Rom line interpolation).

### Fixed
- **Month label mismatch**: previously displayed the *previous* month (e.g., “September” in October); now correctly shows the **current month (MTD)**.
- **Vertical spacing**: fixed layout compression caused by the summary card; collapsible design restores proper scroll area for the workout feed.

[0.6.6]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.6  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.6...HEAD

## [0.6.5] - 2025-10-26
### Added
- **Profile → Progress: Advanced stats & subtabs**
- New **subtabs**: **Activity**, **Intensity**, **Consistency**.
- **Activity**: shows either **Workouts** or **Score** per bucket (Week/Month/Year).
- **Intensity**: shows **average score per bucket** (total score ÷ workouts).
- **Consistency**: shows **workout distribution by type** (strength/cardio/sport) as a **donut chart** (iOS 17+ `SectorMark`) with **bar chart fallback** on older iOS. Displays **total trained duration** (hh:mm).
- Context-aware UI: the **Metric** picker (Workouts/Score) only appears in **Activity**.

### Changed
- **Progress data pipeline**
- Refactored `loadProgress()` to compute **counts**, **scores**, **per-workout averages**, **type distribution**, and **total duration** in one pass.
- Duration now coalesces from multiple sources: `workouts.duration_min`, or `cardio_sessions.duration_sec` / `sport_sessions.duration_sec` (converted to minutes).
- Reused the existing **time bucketing** (day/month) and labels; preserved the **smooth line** (`.interpolationMethod(.catmullRom)`).
- **Charts styling**
- Unified plot area styling (soft gray background with rounded corners) across line, donut, and bar charts.
- Dynamic Y-axis margins kept to prevent line clipping at zero across **Activity** and **Intensity**.

### Fixed
- Prevented **line clipping at 0** in **Intensity** when buckets have low or zero values.
- Avoided duplicate `.chartPlotStyle` in the same chart to remove potential layout warnings.

### Database
- **No schema changes.**
- Read paths broadened to include `cardio_sessions.duration_sec` and `sport_sessions.duration_sec` when `workouts.duration_min` is missing. RLS unchanged.

[0.6.5]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.5
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.5...HEAD

## [0.6.4] - 2025-10-26  
### Added  
- **Remember Me (Login)**  
- Introduced a new **“Remember Me”** toggle in the login screen.  
- When enabled, the user’s session is now **persisted locally** across app restarts, allowing instant auto-login without requiring credentials again.  
- Implemented secure session restoration through Supabase Auth (`supabase.auth.session`) with automatic refresh of access tokens when the app launches.  
- Added local flag storage using `@AppStorage("rememberMe")` to maintain state between sessions.  

### Changed  
- **ProfileView (Progress tab / Chart)**  
- Updated the **chart background** to use a **soft translucent gray** (`Color.gray.opacity(0.18)`) that subtly blends with the profile gradient, giving the chart better separation without breaking visual consistency.  
- Added **rounded corners** (`cornerRadius: 12`) to the chart’s plot area for a cleaner and more modern look.  
- Smoothed the chart line using `.interpolationMethod(.catmullRom)` for more natural curves between data points.  
- Introduced a **dynamic Y-axis range** with small top and bottom margins (`chartYScale(domain: yLower...yUpper)`), ensuring the line never gets cut off even when values reach `0`.  
- Minor spacing refinements for consistent horizontal padding and height alignment across “Week”, “Month”, and “Year” modes.  

### Fixed  
- **Chart rendering edge cases**  
- Fixed visual clipping when all progress values were `0` — the chart line is now always visible with a safe margin below the X-axis.  
- Prevented duplicate `.chartPlotStyle` modifiers that could cause layout warnings in some SwiftUI versions.  
- **Session persistence**  
- Fixed login sessions being lost after app restart when using Supabase Auth.  
- Improved token refresh handling to prevent “Auth session missing” errors during startup.  

[0.6.4]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.4  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.4...HEAD  

## [0.6.3] - 2025-10-22  
### Added  
- Sport workouts (extended metadata):  
- Added full support for sport-specific fields such as `score_for`, `score_against`, `match_score_text`, `location`, and `duration_sec`.  
- Enables complete recording of sports like padel, football, or tennis with full match details and custom notes.  
- Integrated seamlessly with AddWorkoutSheet and EditWorkoutMetaSheet for editing and displaying these values.  

### Changed  
- Database function:  
- The RPC `create_sport_workout_v1` was rewritten to accept all new sport-related fields and ensure consistent data insertion into `public.sport_sessions`.  
- Improved backward compatibility: still works with previous payloads that only provided `p_duration_min`.  
- Simplified duration handling — automatically converts minutes to seconds when needed.  

### Fixed  
- WorkoutDetailView / EditWorkoutMetaSheet:  
- Fixed missing sport data (duration, result, match score, or location) after saving.  
- Root cause: some fields were not persisted by the old RPC — now properly stored and displayed.  

### Database  
- Updated: `create_sport_workout_v1(p jsonb)` now includes all sport session columns and improved parameter handling.  
- No schema or trigger changes — only logic updates within the existing function.  

[0.6.3]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.3  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.3...HEAD  

## [0.6.2] - 2025-10-22
### Added
- **RankingView (v1)**:
- New **leaderboard screen** showing global and friends rankings by **total score**.
- Filtering by **scope** (Global / Friends), **period** (Today / Week / Month / All-time), **type** (All / Strength / Cardio / Sport), **sex**, and **age band**.
- Each row displays **rank**, **avatar**, **username**, **total score**, and **workouts count**.
- Introduced a new visual design with **SectionCard** components for cleaner card-style layout.
- Integrated gradient background consistent with app design.

### Changed
- **Leaderboard SQL (get_leaderboard_v1)**:
- Added `workout_id` to the `src` CTE to fix incorrect workout counting.
- Replaced  
`count(distinct case when score is not null then started_at::date end)`  
with  
`count(distinct workout_id)`  
to correctly count all workouts rather than workout days.
- Clarified filters for **period**, **scope**, **sex**, and **age** for more accurate aggregation.
- Maintains total score aggregation across all algorithms by default.

### Fixed
- **Workouts count mismatch**: previously only counted distinct training days (e.g., 8) instead of real workouts (e.g., 34).  
Now the count matches `count(distinct workouts.id)` from the database.
- **Friends/Global visibility issues**: added missing RLS policies to ensure visible workouts, profiles, and scores from followed users.
- **UI layout**: fixed long type-checking compile time by breaking `RankingView` into subviews and adding a local `SectionCard` definition.
- **AnyJSON encoding errors**: replaced generic initializers with lightweight helpers (`ajString`, `ajInt`) to ensure stable RPC param serialization.

### Database
- **Function:** `get_leaderboard_v1(...)` updated for correct workout counting and improved filters.
- **RLS:** added visibility policies for:
- `workouts_select_visible`
- `workout_scores_select_visible`
- `profiles_select_visible_min`
- **No schema or trigger changes.**

[0.6.2]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.2  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.2...HEAD

## [0.6.1] - 2025-10-22
### Added
- **Workout duplication**: from `WorkoutDetailView` → “…” menu → **Duplicate** now opens the **Add** tab with a pre-filled form depending on the workout type:
- *Strength*: copies all exercises (order, notes) and every **set** (reps, weight, RPE, rest).
- *Cardio*: copies modality, distance, duration, HR, pace, and elevation gain.
- *Sport*: copies sport, duration, result, and session notes.
- Always resets the date to **now** and clears any previous `ended_at` value.
- **Save feedback**: after pressing `Save` in `AddWorkoutSheet`, a **success banner** (“Workout saved! 💪”) now appears, the form is **reset**, and the app **redirects automatically to Home**.
- **Exercise picker – new sorting modes**:
- **Favorites** (with instant optimistic UI updates).
- **Most used** (via `get_exercises_usage` RPC).
- **Recently used** (sorted by last_used_at DESC, safe fallback if null).
- Improved search and clearer row labels showing alias/category.

### Changed
- **Duplication flow integrated with global navigation**:
- Uses `AppState.openAdd(with:)` to inject the **AddWorkoutDraft** (`app.addDraft`) and trigger sheet recreation via `app.addDraftKey`.
- The Add tab now rebuilds dynamically with `.id(app.addDraftKey)` when a new draft is passed.
- **Exercise picker UX improvements**:
- Enlarged touch area for the favorite ★ button.
- Cleaner visual hierarchy and separation from the main tap gesture.

### Fixed
- **Duplicate button not working**: now correctly generates the draft, switches to the **Add** tab, and opens the form in “edit mode” with duplicated data.
- **AddWorkoutSheet retained old data after saving**: now displays a success banner, resets the form state, and redirects to **Home** to avoid stale state confusion.
- Fixed navigation inconsistencies when closing sheets or returning from duplicated workouts.

### Database
- No schema changes.
- Reused existing RPC `get_exercises_usage` for both “Most used” and “Recently used” exercise filters.

[0.6.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.1
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.1...HEAD

## [0.6.0] - 2025-10-21
### Added
- **Database (RLS Policies):**:
•    Added new visibility policies to allow users to see workouts, exercises, and sets from people they follow.
•    New policies created:
•    we_select_visible → grants read access to workout_exercises from followed users.
•    es_select_visible → grants read access to exercise_sets belonging to followed workouts.
•    follows_select_own → allows users to read their own follow relationships.
•    Verified existing cardio_sessions and sport_sessions RLS for owner-only visibility.
•    All new policies are permissive, non-destructive, and backward compatible.

### Changed
•    EditWorkoutMetaSheet (UI):
•    Redesigned the “GENERAL” section with a new SectionCard layout for a cleaner and more consistent visual style.
•    Fixed Notes field truncation issue — now expands properly with vertical text input.
•    Improved padding, spacing, and dividers for better hierarchy.
•    Adopted consistent FieldRowPlain layout across fields (Title, Notes, Started, Finished, Intensity).

### Fixed
•    Notes text field now displays full multiline input without clipping.
•    Removed layout warnings related to nested Section blocks inside Form.
•    Ensured smooth save behavior and consistent navigation dismissal after updating workout metadata.

### Database
•    RLS: Added new policies to propagate follower-based visibility for workouts and their related data (exercise_sets, workout_exercises).
•    Verified: No structural changes in schema, triggers, or functions.

[0.6.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.6.0
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.6.0...HEAD

## [0.5.1] - 2025-10-20
### Added
- **FollowersListView / FollowingListView**:
- New screens accessible from the follower/following counters in `ProfileView`.
- Display a searchable list of users with **avatar**, **@username**, and a fully functional **Follow/Unfollow** button.
- Integrated **search bar** for filtering users by name.
- Unified **gradient background** consistent with the rest of the app.
- Direct navigation to each user’s profile by tapping on their row.

### Changed
- **FollowButton** logic refactored to update state instantly without reloading the entire list.
- **Supabase** queries optimized with batched `IN (user_id)` filters to reduce API calls.

### Fixed
- Removed minor compiler warnings (`try?` misuse, unused `MainActor.run` results).
- Navigation behavior fixed so **Follow/Unfollow** button no longer triggers profile navigation when tapped.

[0.5.1]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.5.1
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.5.1...HEAD

---

## [0.5.0] - 2025-10-20
### Added
- **Home (v1)**: paginated feed of workouts (self + following), type filters (All / Strength / Cardio / Sport), and redesigned cards with avatar, title, relative time, type chip, and **score pill**.
- **Search**: user search view with navigation to profile.
- **Follow / Unfollow**: buttons and state logic added to `ProfileView`, with automatic counter refresh.
- **Unified gradient background** applied across all tabs, including profiles of other users.
- **Highlights section in Home**: “Recent PRs” and “Top this week”, with linked profile loading.

### Changed
- **Cards redesigned** (Home and Profile): consistent `WorkoutCardBackground`, type-tinted chips, and unified score pill design.
- **EditProfileSheet**: compact presentation using `.presentationDetents([.fraction(0.42)])` and editor limited to **200 characters**.
- **Profile loading optimization**: introduced `ensureProfilesAvailable` to batch-fetch user profiles and prevent redundant requests.

### Fixed
- **Calendar alignment**: week layout corrected by setting the first weekday to **Monday** (`WEEK_START = 2`) and reordering `shortWeekdaySymbols`. Fixes issue where Monday appeared under Sunday column.
- **Profile gradient background** now displays correctly when viewing other users from **Search**.
- **Workout score aggregation**: multiple `workout_scores` entries per workout are now **summed** to prevent duplicates.
- **Date decoding**: robust ISO8601 parsing (fractional seconds + device timezone) prevents off-by-one issues at month/day boundaries.

### Performance
- **Home pagination** implemented with `range(from:to:)` and batch score loading using `IN (ids)` queries.

[0.5.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.5.0
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.5.0...HEAD

## [0.4.0] - 2025-10-18
### Added
- **ProfileView (v1)** with:
- **Header card**: avatar, @username, follower/following counters, and bio with **Read more / Edit** options.  
- **Bio editing** via `EditProfileSheet`.  
- **Avatar change** using `PhotosPicker` with JPEG resizing and upload to **Supabase Storage** (`avatars/`) + `profiles.avatar_url` update.  
- **Segmented control**: *Calendar · PRs · Settings*.  
- **Calendar tab**:
- Monthly **calendar grid** highlighting days with workouts.  
- **DayWorkoutsList** with per-workout cards showing titles, timestamps, and **score badges** (read from `workout_scores`).  
- **PRs tab**:
- New unified view `public.vw_user_prs` combining strength, cardio, and sport personal records.  
- New **RPC** `public.get_user_prs(p_user_id, p_kind?, p_search?)` (SQL, `STABLE`) to fetch filtered PRs.  
- **RLS (read policies)** applied to:
- `personal_records`: `pr_select_own`
- `endurance_records`: `er_select_own`
- `sport_records`: `sr_select_own`
- **Grants**: `EXECUTE` for `get_user_prs` granted to `authenticated` and revoked from `public`.  
- **Utilities**:
- `JSONDecoder.supabase()` with robust ISO8601 + fractional seconds strategy to handle all Supabase date variations.  

### Changed
- **Profile screen** now loads header (`profiles`, `vw_profile_counts`) and workout history (`workouts`) using **timezone-aware** date ranges (ISO8601 + local zone).  
- Visual refinements across header, workout, and PR cards (material translucency, rounded corners, and subtle shadows).  

### Fixed
- Calendar date range detection now respects **device timezone**, fixing off-by-one issues at month/day boundaries.  
- Safe fallback for invalid or cancelled avatar images during upload.  
- Stable date decoding for mixed timestamp formats returned by Supabase.  

### Database
- **Views:** added `vw_user_prs` (unified PRs view).  
- **Functions:** added `get_user_prs(uuid, text, text)` (new SQL RPC).  
- **RLS:** enforced per-user read policies on `personal_records`, `endurance_records`, and `sport_records`.  
- **Grants:** revoked public access to `get_user_prs`; granted `EXECUTE` to `authenticated`.  

### Notes
- The **floating custom tab bar** (“island” bar) is not included in this release — scheduled for 0.4.1.  
- Next goal: implement user rankings using `vw_user_total_scores` and enhanced PR metrics (localized units, formatting).  

[0.4.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.4.0  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.4.0...HEAD  

---

## [0.3.0] - 2025-10-17
### Added
- **Editable workout creation form (`AddWorkoutSheet`)**: now allows logging strength, cardio, and sport workouts with detailed input fields.  
- **Exercise picker modal (`ExercisePickerSheet`)** with dynamic search in the `exercises` catalog table.  
- **Dynamic exercise cards** with optional alias, notes, perceived intensity, and direct Supabase RPC integration (`create_strength_workout`, `create_cardio_workout`, `create_sport_workout_v1`).  
- **Set tracking system** for strength workouts, including reps, weight, RPE, and per-set notes.  
- **Material-style section cards** with translucent background and rounded corners, matching the app’s overall design.  
- **Automatic Supabase catalog fetching** when selecting the “Strength” workout type.  

### Changed
- Adjusted the **+ / – Stepper buttons** to appear smaller and more proportionate within the set list.  
- Simplified the logic for the **“Add set”** button — new sets now always start as **Set 1**, regardless of previous numbering (better suited for custom workout flows).  
- Improved alignment and spacing of input fields inside each set (Reps, Weight, RPE).  
- Refined the overall **section card layout** with softer shadows and consistent spacing between sections.  

### Fixed
- Fixed an issue where the **exercise picker** remained enabled during catalog loading.  
- Resolved incorrect control alignment inside sets when using the Stepper in compact mode.  
- Optimized conditional catalog loading to prevent multiple simultaneous Supabase calls.  

### Notes
- This version marks the beginning of the **complete workout logging and tracking flow** within the app.  
- Next goal: add persistent user progress tracking and historical workout visualization on the profile screen.  

[0.3.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.3.0  
[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.3.0...HEAD  

---

## [0.2.0] - 2025-10-16
### Added
- **User authentication flow (Sign In / Sign Up)** fully implemented with Supabase Auth.  
- **RegisterView** and **LoginView** redesigned with a clean translucent card style and soft gradients.  
- **Real-time validation** for email, password and username fields.  
- **Sex** and **Date of birth** pickers with modern `LabeledContent` layout (aligned and styled placeholders).  
- **Animated gradient backgrounds** with decorative blur halos for visual polish.  
- **Error handling and feedback banners** for all auth actions (sign-in failures, validation errors, success messages).  
- **Profile auto-creation** on successful signup via Supabase `profiles` upsert.  

### Changed
- **Email confirmation disabled** in Supabase Auth → users are now **auto-confirmed** upon registration.  
- Simplified registration logic (`signUp`) to rely on direct Supabase session instead of waiting for email verification.  
- Unified form aesthetics between login and registration (gray placeholders, rounded translucent panels).  
- Improved password and email validation UX with inline messages.  

### Fixed
- Resolved `Invalid redeclaration of 'rpc'` and decoding issues during precheck RPC call.  
- Corrected SQL trigger syntax to comply with Supabase restrictions (no `$$` delimiters).  
- Fixed session handling (`Cannot find 'session' in scope`) after signup with autoconfirmation.  
- Adjusted form layouts to maintain consistent spacing and alignment across devices.  

### Notes
- Version 0.2.0 marks the **first functional authentication milestone**: users can register, sign in, and manage sessions without external confirmation emails.  
- Next step: integrate user onboarding and persistent workout tracking.  

[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.2.0...HEAD  
[0.2.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.2.0  
[0.1.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.1.0  

---

## [0.1.0] - 2025-10-15
### Added
- **Supabase integration**: initial client (`SupabaseManager`) and connection check.  
- **Authentication state management**: `AppState` + `ProfileGate` (shows login screen when there’s no active session).  
- **Main “island” navigation bar**: custom bottom bar with **Home**, **Search**, **+** button (new workout sheet), and **Profile**.  
- **Base screens**: `HomeView`, `SearchView`, `ProfileView`, `AuthView`, `AddWorkoutSheet`.  
- **Hidden native TabBar** with reserved space for the custom navigation bar.  
- **App icon** (dumbbell + green neural lines).  
- **Initial CI/CD setup with Xcode Cloud**: automated builds and TestFlight distribution directly from Xcode.  
- **Project documentation files**:  
- `README.md`: general description, tech stack and setup guide.  
- `CHANGELOG.md`: version history following [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
- `LICENSE`: MIT license for open-source usage.  
- `.gitignore`: standard Xcode ignores for clean version control.  

### Changed
- Initial project structure (`LiftrApp` → `RootView` as entry point).  
- Replaced GitHub Actions + Fastlane workflows with **Xcode Cloud** for a simplified continuous integration process.  

### Notes
- Main working branch: `devel`.  
- First deployable version connected to Supabase and ready for internal TestFlight testing.  

[Unreleased]: https://github.com/Lilru-tech/Liftr/compare/v0.1.0...HEAD  
[0.1.0]: https://github.com/Lilru-tech/Liftr/releases/tag/v0.1.0
