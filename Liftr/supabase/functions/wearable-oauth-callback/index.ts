import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { appRedirectUrl, verifyState } from "../_shared/wearable-oauth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STATE_SECRET = Deno.env.get("WEARABLE_OAUTH_STATE_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const provider = (url.searchParams.get("provider") ?? "garmin").trim().toLowerCase();
    const state = url.searchParams.get("state") ?? "";
    const oauthToken = url.searchParams.get("oauth_token") ?? "";
    const oauthVerifier = url.searchParams.get("oauth_verifier") ?? "";

    if (!STATE_SECRET) {
      return Response.redirect(appRedirectUrl(provider, "error", "not_configured"), 302);
    }

    const stateData = await verifyState(state, STATE_SECRET);
    if (!stateData?.user_id) {
      return Response.redirect(appRedirectUrl(provider, "error", "invalid_state"), 302);
    }

    const userId = stateData.user_id;

    if (!oauthToken || !oauthVerifier) {
      return Response.redirect(appRedirectUrl(provider, "error", "missing_oauth_params"), 302);
    }

    const { error: upsertErr } = await supabase.from("wearable_connections").upsert(
      {
        user_id: userId,
        provider,
        status: "active",
        access_token: oauthToken,
        refresh_token: oauthVerifier,
        connected_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        metadata: { oauth_stage: "access_pending_exchange" },
      },
      { onConflict: "user_id,provider" },
    );

    if (upsertErr) {
      console.error("[wearable-oauth-callback] upsert", upsertErr);
      return Response.redirect(appRedirectUrl(provider, "error", "storage_failed"), 302);
    }

    return Response.redirect(appRedirectUrl(provider, "connected"), 302);
  } catch (e) {
    console.error("[wearable-oauth-callback]", e);
    return Response.redirect(appRedirectUrl("garmin", "error", "internal_error"), 302);
  }
});
