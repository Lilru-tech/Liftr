# Liftr — 5-minute stakeholder demo script

**Total time:** ~5:00 · **Platform:** iOS or Android (same tab structure)  
**Prerequisites:** Logged-in demo account with 2+ followed users, one published cardio with route, territory cells near demo location optional.

**Recording tips:** Screen record at 1080p; hide status-bar personal data; use TestFlight or internal build labeled “Liftr demo”.

---

## 0:00–0:30 — Hook (Journey A — Home & graph)

| Time | On screen | Say |
|------|-----------|-----|
| 0:00 | **Home** tab — scroll feed | “This is Liftr’s social feed — real workouts from people you follow, not an algorithmic For You page.” |
| 0:10 | Tap a **workout card** → detail | “Every post is a full session: strength, cardio, or sport — with score, likes, and comments.” |
| 0:20 | Back → show **filter chips** (strength / cardio / sport) | “Athletes filter by modality — one app for the gym and the road.” |
| 0:28 | **Profile** tab → follower count or **Search** → follow suggestion | “The graph is follow-based — you train with people you know.” |

**Backend callout (optional, 5 sec):** Home loads via `get_home_feed_page_v1` — one round-trip for feed + scores + likes.

---

## 0:30–1:45 — Core value (Journey B — Strength workout)

| Time | On screen | Say |
|------|-----------|-----|
| 0:30 | **Add** tab → **Strength** → pick 2 exercises | “Logging a lift takes seconds — catalog search, favorites, muscle filters.” |
| 0:45 | **Start workout** → **Active strength** | “In-session UX is native: supersets, drop sets, personalized rest timers from your history.” |
| 1:00 | Log **one set** (reps + weight) → mark complete | “Data syncs through secure server RPCs — same rules on iOS and Android.” |
| 1:15 | Show **Live Activity** (iOS) or **notification / widget** (Android) if available | “You can stay in the workout without living inside the app.” |
| 1:25 | **Finish workout** → publish | “Publish pushes to the feed, updates XP, and can unlock achievements server-side.” |
| 1:40 | **Home** — show new workout at top | “Your crew sees it immediately — that’s the social loop.” |

**Skip if short on time:** Do not edit meta; one exercise is enough.

---

## 1:45–3:00 — Differentiator (Journey C — Cardio + territory)

| Time | On screen | Say |
|------|-----------|-----|
| 1:45 | Open an existing **cardio workout** with map route (or quick-add run) | “Outdoor cardio stores GPS as GeoJSON — same pipeline as Health import.” |
| 2:00 | **Workout detail** — map / distance / pace | “Strava-class route detail, inside Liftr’s social graph.” |
| 2:15 | Navigate to **Territory map** (profile hub or post-capture toast) | “Here’s what sets us apart: **territory capture** on publish.” |
| 2:30 | Pan map — colored cells / city overlay | “Cells you earn by running or riding outdoors — others can take them.” |
| 2:45 | Show **takeover** or capture summary if available | “Push notifications fire on takeovers — lightweight RPG on top of real training.” |
| 2:55 | Mention **Apple Health / Health Connect** (Profile → import) | “Imports dedupe automatically — no double posts when you also track on a watch.” |

**Backend callout:** `apply_territory_capture_v1` runs on publish; clients cannot fake cells (RPC-only writes).

---

## 3:00–4:00 — Competition layer (Journey D — Rankings & goals)

| Time | On screen | Say |
|------|-----------|-----|
| 3:00 | **Ranking** tab → switch metric (e.g. score, volume, goals completed) | “Dozens of leaderboards — global or friends, day/week/month.” |
| 3:20 | Toggle **Friends** scope | “Status and rivalry without leaving the app.” |
| 3:35 | **Profile** → **Weekly goals** or goals card | “Weekly goals recompute from real published work — habit, not vanity metrics.” |
| 3:50 | Optional: **Achievements** grid (2 sec) | “Achievements are evaluated in the database when you train — collection meta-game.” |

---

## 4:00–5:00 — Social depth & close (Journey E + recap)

| Time | On screen | Say |
|------|-----------|-----|
| 4:00 | **Workout detail** → **comment** with `@mention` if demo user exists | “Comments support mentions — only people you follow, validated server-side.” |
| 4:15 | **Messages** / chat icon → thread | “DMs and shares: send a workout, routine, segment, or achievement to a training partner.” |
| 4:30 | Optional: **Segment** detail or leaderboard (10 sec) | “Segments are Strava-style KOMs with coverage scoring — fair matching on GPS.” |
| 4:45 | Back to **Home** | “Log → publish → rank → chat → territory — one loop, two native apps, one Supabase backend.” |
| 4:55 | Title card or app icon | “Liftr — social progress and playable territory on every workout.” |

---

## Fallback paths (if demo data missing)

| Missing | Substitute |
|---------|------------|
| No followed users | Use **Search** → trending workouts; explain feed fills after follow |
| No territory cells | Show territory map empty state + screenshot in deck slide 4 |
| No GPS route | Open **Compare workouts** from a strength post instead (1.14 feature) |
| Chat empty | Show share sheet from workout detail without sending |

---

## Post-demo Q&A cheat sheet

| Question | Short answer |
|----------|--------------|
| iOS vs Android? | Feature parity on five tabs; native UX per platform (Live Activity vs FGS widget). |
| Backend? | Supabase Postgres + PostGIS; business logic in RPCs; 79 migrations in repo. |
| Revenue? | Ads + Premium ad-free; Play Billing on Android. |
| Moat? | Territory + strength depth + server-enforced game rules. |
| Scale risks? | Territory spatial IO — actively capped and monitored (`docs/supabase-disk-io-baseline.md`). |

---

## File references for demo prep

| Journey | iOS | Android |
|---------|-----|---------|
| Home | `Liftr/HomeView.swift` | `ui/home/HomeTabScreen.kt` |
| Active strength | `Liftr/ActiveStrengthWorkoutView.swift` | `ui/active/ActiveStrengthWorkoutScreen.kt` |
| Territory map | `Liftr/TerritoryMapView.swift` | `ui/territory/` |
| Rankings | `Liftr/RankingView.swift` | `ui/ranking/` |
| Chat | `Liftr/Chat/` | `ui/chat/` |
