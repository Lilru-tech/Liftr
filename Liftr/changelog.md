# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
- …

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
