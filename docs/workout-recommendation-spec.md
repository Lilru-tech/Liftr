# Workout recommendation spec (“Suggest next session”)

Client-only feature: iOS `WorkoutRecommendationService.swift`, Android `WorkoutRecommendationEngine.kt` + `WorkoutRecommendationCardioSport.kt`. UI: `WorkoutRecommendationFlowView` / `AddWorkoutRecommendationDialog`.

## Constants

| Constant | Value |
|----------|-------|
| `lookbackCount` | 10 published workouts per kind |
| `targetExerciseCount` | 5 |
| `defaultSetsPerExercise` | 3 |
| `defaultReps` | 12 |
| `defaultRestBetweenSetsSec` | 90 |
| `rpeWeightDeltaKg` | ±2.5 |
| `recoveryDeprioritizeHours` | 48 |
| `favoriteSelectionBoost` | 2× in shuffle pools |
| `prChaseProximityRatio` | within 5% of PR max weight |
| `prCapIncrementKg` | +2.5 above PR |
| `beginnerStrengthSessionThreshold` | &lt;5 published strength workouts |
| `networkLookbackDays` | 7 (followees, opt-in) |

## Data sources

| Source | Strength | Cardio | Sport |
|--------|----------|--------|-------|
| `recentHistory` | Exercises from last 10 | Activities logged | Sports logged |
| `fullCatalog` | All catalog exercises | All activity types | All sport types |
| `myRoutines` | Saved `strength_routine_*` (auto-pick + pick another) | — | Hyrox via `hyrox_routine_*` when sport |
| `networkInspired` | Aggregate followee exercises (opt-in toggle) | Aggregate followee activities | — |
| `hyrox` / `hyroxRace` | — | — | Hyrox modes |

## Strength modes

| Mode | Behavior |
|------|----------|
| `prioritizeUndertrainedMuscles` | Time-weighted set counts; deprioritize muscles trained &lt;48h; favor bottom 3 muscles; favorites boosted |
| `prioritizeFrequentLifts` | Exercises in most workouts; latest sets + RPE progression |
| `chasePRs` | Exercises within 5% of strength PR (`get_user_prs`); else fallback to frequent lifts |

## Enrichment inputs

Loaded once per generate (`WorkoutRecommendationContext`):

- `profiles`: weight, sex, date_of_birth → cold-start load scaling
- `user_favorite_exercises` → selection bias
- `get_user_prs(p_user_id, 'strength')` → PR cap / chase mode
- `weekly_goals` + `weekly_goal_results` (current week) → rationale + duration nudges
- `follows` + followee workouts (7d, opt-in) → networkInspired pool

## Progression

1. Latest published session per exercise (time-weighted window).
2. RPE: avg &lt;8 → +2.5 kg or add set/reps; avg ≥9 → −2.5 kg.
3. PR cap: suggested weight ≤ PR + 2.5 kg when PR exists for exercise label match.

## Outputs

- **Strength**: `StrengthRecommendationOutput` — exercises, session rationale, muscle freshness chips, optional routine name.
- **Cardio / sport**: existing types; rationale may append goal nudge.

## iOS ↔ Android parity checklist

- [ ] Same enum cases for data sources and strength modes
- [ ] Same constants and RPE rules
- [ ] Context loader fields match
- [ ] Routine source uses same pick + “pick another” UX
- [ ] Network inspired requires explicit opt-in on both platforms
- [ ] Regenerate on result screen (same options, new shuffle)
- [ ] Android cardio/sport result uses labeled fields like iOS
- [ ] Suggest enabled in routine template editor quick actions
- [ ] Partial stat load failures surface footnote (no silent empty catch without UI note)

## Related (not this feature)

- `get_weekly_goal_recommendation` — numeric goal targets only
- Saved routines picker — manual apply, separate from suggest engine
