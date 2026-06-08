import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/wearable-oauth.ts";
import { mapGarminActivityType, parseGpxTrackPoints, type RoutePoint } from "../_shared/gpx-parse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GARMIN_WEBHOOK_SECRET = Deno.env.get("GARMIN_WEBHOOK_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

type GarminActivitySummary = {
  userId?: string;
  summaryId?: string;
  activityId?: string;
  activityType?: string;
  startTimeInSeconds?: number;
  durationInSeconds?: number;
  startTimeOffsetInSeconds?: number;
};

type GarminWebhookPayload = {
  activityFiles?: Array<{
    userId?: string;
    summaryId?: string;
    fileType?: string;
    callbackURL?: string;
    activityType?: string;
    startTimeInSeconds?: number;
    durationInSeconds?: number;
  }>;
  activities?: GarminActivitySummary[];
};

async function verifyWebhook(req: Request): Promise<boolean> {
  if (!GARMIN_WEBHOOK_SECRET) return true;
  const token = req.headers.get("X-Garmin-Webhook-Secret")?.trim() ?? "";
  if (!token) return false;
  const a = new TextEncoder().encode(token);
  const b = new TextEncoder().encode(GARMIN_WEBHOOK_SECRET);
  if (a.length !== b.length) return false;
  return crypto.subtle.timingSafeEqual(a, b);
}

async function resolveLiftrUserId(providerUserId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("wearable_connections")
    .select("user_id")
    .eq("provider", "garmin")
    .eq("provider_user_id", providerUserId)
    .eq("status", "active")
    .maybeSingle();
  if (error) {
    console.error("[garmin-activity-webhook] resolve user", error);
    return null;
  }
  return data?.user_id ?? null;
}

async function fetchRoutePoints(callbackURL: string): Promise<RoutePoint[]> {
  const res = await fetch(callbackURL);
  if (!res.ok) throw new Error(`callback fetch failed: ${res.status}`);
  const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
  const text = await res.text();
  if (contentType.includes("gpx") || text.includes("<gpx")) {
    return parseGpxTrackPoints(text);
  }
  return [];
}

async function upsertRouteJob(args: {
  userId: string;
  providerActivityId: string;
  startedAt: string;
  endedAt: string | null;
  durationSec: number | null;
  activityCode: string | null;
  routePoints: RoutePoint[];
  metadata: Record<string, unknown>;
}): Promise<void> {
  if (args.routePoints.length < 2) return;
  const { error } = await supabase.from("external_workout_route_jobs").upsert(
    {
      user_id: args.userId,
      provider: "garmin",
      provider_activity_id: args.providerActivityId,
      started_at: args.startedAt,
      ended_at: args.endedAt,
      duration_sec: args.durationSec,
      activity_code: args.activityCode,
      route_points: args.routePoints,
      status: "pending",
      metadata: args.metadata,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,provider,provider_activity_id" },
  );
  if (error) console.error("[garmin-activity-webhook] upsert job", error);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  if (!(await verifyWebhook(req))) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  try {
    const payload = (await req.json()) as GarminWebhookPayload;
    const files = payload.activityFiles ?? [];

    for (const file of files) {
      const providerUserId = String(file.userId ?? "").trim();
      const providerActivityId = String(file.summaryId ?? file.activityType ?? "").trim();
      const callbackURL = String(file.callbackURL ?? "").trim();
      if (!providerUserId || !providerActivityId || !callbackURL) continue;

      let userId = await resolveLiftrUserId(providerUserId);
      if (!userId) {
        const { data: conn } = await supabase
          .from("wearable_connections")
          .select("user_id")
          .eq("provider", "garmin")
          .eq("status", "active")
          .is("provider_user_id", null)
          .limit(1)
          .maybeSingle();
        userId = conn?.user_id ?? null;
        if (userId) {
          await supabase
            .from("wearable_connections")
            .update({ provider_user_id: providerUserId, updated_at: new Date().toISOString() })
            .eq("user_id", userId)
            .eq("provider", "garmin");
        }
      }
      if (!userId) continue;

      const routePoints = await fetchRoutePoints(callbackURL);
      const startSec = file.startTimeInSeconds;
      const startedAt = startSec
        ? new Date(startSec * 1000).toISOString()
        : new Date().toISOString();
      const durationSec = file.durationInSeconds ?? null;
      const endedAt = durationSec != null && startSec != null
        ? new Date((startSec + durationSec) * 1000).toISOString()
        : null;

      await upsertRouteJob({
        userId,
        providerActivityId,
        startedAt,
        endedAt,
        durationSec,
        activityCode: mapGarminActivityType(file.activityType),
        routePoints,
        metadata: {
          file_type: file.fileType ?? null,
          activity_type: file.activityType ?? null,
          source_bundle: "com.garmin.connect.mobile",
        },
      });
    }

    return jsonResponse({ ok: true, processed_files: files.length });
  } catch (e) {
    console.error("[garmin-activity-webhook]", e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
