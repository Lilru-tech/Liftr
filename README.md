# Liftr
iOS app to track workouts, progress and gym performance.

- **iOS (Swift / SwiftUI):** proyecto en `Liftr.xcodeproj` y `Liftr/`.
- **Android (Kotlin / Jetpack Compose, Google Play):** módulo en [android/README.md](android/README.md) y [docs/android-strategy.md](docs/android-strategy.md).

## Publicación
Guía de **App Store (iOS)** y **Google Play (Android)**: [docs/publishing.md](docs/publishing.md). Detalle AAB, claves y pistas: [docs/android-play-release.md](docs/android-play-release.md).

**iOS CI (Xcode Cloud):** un solo workflow **Devel** en rama `devel` — [docs/xcode-cloud-workflows.md](docs/xcode-cloud-workflows.md).

**Protección de `main`:** [docs/github-branch-protection.md](docs/github-branch-protection.md) — script `scripts/protect-main-branch.sh`.

## Documentación de ingeniería

- **Arquitectura y dominios:** [docs/liftr-app-overview.md](docs/liftr-app-overview.md)
- **Contratos Supabase:** [docs/backend-contracts.md](docs/backend-contracts.md)
- **Pet combat arena (ops):** [docs/pet-combat-arena.md](docs/pet-combat-arena.md) — energía, cooldown, handicap/hardcore, balance v4/v5 y verify
- **Paridad Android:** [docs/android-parity-inventory.md](docs/android-parity-inventory.md)

## Stakeholder materials
Executive deck, 5-minute demo script, and technical API appendix: [docs/stakeholder/](docs/stakeholder/).
