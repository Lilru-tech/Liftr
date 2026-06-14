# Liftr 🏋️‍♂️
Your personal fitness tracking companion.  
Track your workouts, manage progress, and stay motivated.

## 🚀 Features
- Supabase integration (auth, data sync)
- Custom navigation menu (Home, Search, Add, Profile)
- Authentication gate (`ProfileGate`)
- Modular SwiftUI architecture

## 🧰 Tech Stack
- SwiftUI
- Supabase
- Xcode Cloud (iOS builds / TestFlight)
- GitHub Actions (Android, Supabase edge, `devel` → `main` sync)

## ☁️ CI/CD
**iOS:** **Xcode Cloud** workflow **Devel** — one build per push to branch `devel` (TestFlight). Do not add a second workflow on `devel`; see [docs/xcode-cloud-workflows.md](../docs/xcode-cloud-workflows.md).

**Other:** GitHub Actions under `.github/workflows/` (not iOS archives).

## 🏗️ Project Structure
📁 Liftr
├── AddWorkoutSheet
├── AppState
├── CustomTabBar
├── HomeView
├── ProfileGate
├── RootView
├── SearchView
├── SupabaseManager
└── Assets
## 🧪 Development
Clone the repo and open in Xcode:
bash
git clone https://github.com/Lilru-tech/Liftr.git
cd Liftr
open Liftr.xcodeproj

