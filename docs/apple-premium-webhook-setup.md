# Apple App Store Server Notifications (Premium)

Liftr uses **two** billing endpoints:

| Endpoint | Who calls it |
|----------|----------------|
| `process-billing-webhook` | Internal tools, Google Play adapter, manual `curl` tests (shared secret) |
| `process-apple-app-store-notification` | **Apple only** (App Store Server Notifications V2) |

Apple sends a JWS `signedPayload`, not the normalized JSON used by `process-billing-webhook`. The Apple function decodes the notification, reads `appAccountToken` (your Supabase `auth.users` id set at purchase time in iOS), and upserts `user_subscriptions`.

## What you must do in App Store Connect (cannot be automated from this repo)

Only someone with **Admin / App Manager** access to your Apple Developer team can complete this.

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com).
2. **My Apps** → select **Liftr** (your iOS app).
3. In the left sidebar, open **App Information** (under *General*).
4. Scroll to **App Store Server Notifications**.
5. **Production Server URL** → **Set Up URL** (or **Edit**):
   - URL (replace with your project ref if different):

     `https://rjzhaafvkxmvlnpsikbi.supabase.co/functions/v1/process-apple-app-store-notification`

   - **Version:** **Version 2 Notifications**
   - **Save**
6. **Sandbox Server URL** (recommended for TestFlight / sandbox purchases):
   - Use the **same URL** as production unless you run a separate Supabase project for dev.
   - **Version 2**
   - **Save**
7. Use **Send Test Notification** (if shown) and confirm Supabase function logs return HTTP 200.

Apple requires **HTTPS** and a quick **2xx** response. The function returns `200` even when it skips unknown products or missing `appAccountToken` (so Apple does not retry forever).

## Deploy the Supabase function (you or CI)

From the repo root:

```bash
cd Liftr
supabase functions deploy process-apple-app-store-notification
```

Optional secret (defaults to `com.liftr.premium.monthly`):

```bash
supabase secrets set APPLE_PREMIUM_PRODUCT_ID="com.liftr.premium.monthly"
```

Ensure the database migration `20260524140000_user_subscriptions_premium_v1.sql` is applied on the same project.

## iOS requirement: `appAccountToken`

On subscribe, the app passes the signed-in user’s UUID as StoreKit `appAccountToken`. Apple echoes it in server notifications so the backend knows which `user_id` to update.

Implemented in `Liftr/ProfileView.swift` (`product.purchase(options: [.appAccountToken(userId)])`).

**Important:** Subscriptions started **before** this change may not include `appAccountToken`. Those users need a new purchase/restore after updating the app, or a one-off manual `process-billing-webhook` `curl` with their `user_id`.

## Verify end-to-end

1. Sign in on a **sandbox** Apple ID on a dev build.
2. Subscribe to Premium in Profile.
3. In App Store Connect, confirm notifications are enabled and check **Supabase → Edge Functions → Logs** for `process-apple-app-store-notification`.
4. In Supabase SQL:

   ```sql
   select * from user_subscriptions where user_id = '<your-user-uuid>';
   ```

5. Restart the app or sign in again → ads should hide (`get_user_premium_status_v1` → `true`).

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Apple test notification 200 but no DB row | TEST payload may omit `appAccountToken`; run a real sandbox subscription instead. |
| Log `skipped: no_app_account_token` | Purchase happened without signed-in user or old app build. |
| Log `skipped: other_product` | Wrong `APPLE_PREMIUM_PRODUCT_ID` secret vs App Store product id. |
| Premium still false in app | Webhook not deployed, migration missing, or client not refreshed (`refreshPremiumStatus`). |
| Used `process-billing-webhook` URL in Apple | Wrong endpoint; Apple must use `process-apple-app-store-notification`. |

## Security note

The Apple handler decodes JWS payloads to read transaction fields. For stricter production hardening, add Apple’s certificate chain verification (App Store Server Library) in a follow-up. Do not point Apple at `process-billing-webhook`; that endpoint expects your private `BILLING_WEBHOOK_SECRET`, which Apple does not send.
