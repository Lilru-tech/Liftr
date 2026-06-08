import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonResponse, signState } from "../_shared/wearable-oauth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const GARMIN_CONSUMER_KEY = Deno.env.get("GARMIN_CONSUMER_KEY") ?? "";
const STATE_SECRET = Deno.env.get("WEARABLE_OAUTH_STATE_SECRET") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "unauthorized" }, 401);

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) return jsonResponse({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const provider = String((body as Record<string, unknown>).provider ?? "garmin").trim().toLowerCase();
    if (provider !== "garmin") {
      return jsonResponse({ error: "unsupported_provider" }, 400);
    }
    if (!GARMIN_CONSUMER_KEY || !STATE_SECRET) {
      return jsonResponse({ error: "garmin_not_configured" }, 503);
    }

    const callbackUrl = `${SUPABASE_URL}/functions/v1/wearable-oauth-callback?provider=garmin`;
    const statePayload = new URLSearchParams({
      user_id: user.id,
      provider: "garmin",
      ts: String(Date.now()),
    }).toString();
    const state = await signState(statePayload, STATE_SECRET);

    const requestTokenUrl = new URL("https://connectapi.garmin.com/oauth-service/oauth/request_token");
    const oauthParams = new URLSearchParams({
      oauth_consumer_key: GARMIN_CONSUMER_KEY,
      oauth_signature_method: "HMAC-SHA1",
      oauth_timestamp: String(Math.floor(Date.now() / 1000)),
      oauth_nonce: crypto.randomUUID().replace(/-/g, ""),
      oauth_version: "1.0",
      oauth_callback: `${callbackUrl}&state=${encodeURIComponent(state)}`,
    });

    return jsonResponse({
      provider: "garmin",
      authorization_url: `https://connect.garmin.com/oauthConfirm?oauth_token=PENDING&${oauthParams.toString()}`,
      message: "Complete Garmin OAuth in browser. Configure GARMIN_CONSUMER_KEY for production token exchange.",
      state,
      callback_url: callbackUrl,
    });
  } catch (e) {
    console.error("[wearable-oauth-start]", e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
