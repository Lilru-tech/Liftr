# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
- …

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
