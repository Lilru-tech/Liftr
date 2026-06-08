# Garmin Connect Developer Program — Liftr setup

Liftr’s external GPS route sync uses the **Garmin Connect Activity API** ($0 licensing for approved business developers). Submit this application in parallel with engineering work.

## Application

1. Open [Garmin Connect Developer Program](https://developer.garmin.com/gc-developer-program/overview/).
2. Request access as **Liftr** (business / app on the App Store).
3. Describe the use case: fetch activity GPS from Garmin Connect and attach `HKWorkoutRoute` to matching Apple Health workouts when Garmin’s Health sync omits routes.
4. Typical review: **1–4 business days** for initial approval; integration verification **1–4 weeks**.

## After approval — API app configuration

Create an app in the Garmin Developer Portal and set:

| Setting | Value |
|---------|--------|
| OAuth redirect | `https://rjzhaafvkxmvlnpsikbi.supabase.co/functions/v1/wearable-oauth-callback?provider=garmin` |
| Activity API | Enabled (FIT / GPX / TCX) |
| Push / webhook URL | `https://rjzhaafvkxmvlnpsikbi.supabase.co/functions/v1/garmin-activity-webhook` |

## Supabase secrets (Edge Functions)

Set in Supabase Dashboard → Project Settings → Edge Functions → Secrets:

```
GARMIN_CONSUMER_KEY=<from Garmin portal>
GARMIN_CONSUMER_SECRET=<from Garmin portal>
WEARABLE_OAUTH_STATE_SECRET=<random 32+ char string>
GARMIN_WEBHOOK_SECRET=<optional shared secret for webhook verification>
```

## iOS deep link

Garmin OAuth completion redirects through the edge callback, which redirects to:

`com.davidgomez.Liftr://wearable-callback?provider=garmin&status=connected`

Handle this in `LiftrApp` / `RootView` alongside the existing auth callback.

## Evaluation environment

Garmin provides sample users and activities in the evaluation environment. Use them to validate `garmin-activity-webhook` GPX/FIT ingestion before production.

## Fitbit fallback (Phase 2)

If Garmin approval is delayed, register at [dev.fitbit.com](https://dev.fitbit.com) and configure the same edge functions with `provider=fitbit` (OAuth 2.0 PKCE).
