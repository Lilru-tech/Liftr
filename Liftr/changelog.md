# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
- …

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
