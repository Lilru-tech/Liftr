import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const NOMINATIM_BASE = "https://nominatim.openstreetmap.org";
const USER_AGENT = "Liftr/1.0 (territory-municipality-resolve)";

type QueueRow = {
  bucket_lat: number;
  bucket_lon: number;
  sample_lat: number;
  sample_lon: number;
  attempts: number;
};

type NominatimReverse = {
  place_id?: number;
  osm_type?: string;
  osm_id?: number;
  lat?: string;
  lon?: string;
  display_name?: string;
  boundingbox?: string[];
  geojson?: { type?: string; coordinates?: unknown };
  address?: Record<string, string | undefined>;
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function slugify(value: string) {
  return value
    .normalize("NFKD")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[\s_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function municipalityLabel(address: Record<string, string | undefined> | undefined, fallback: string) {
  const candidates = [
    address?.city,
    address?.town,
    address?.village,
    address?.municipality,
    address?.county,
    address?.state,
    fallback,
  ];
  for (const candidate of candidates) {
    if (candidate && candidate.trim().length > 0) {
      return candidate.trim();
    }
  }
  return fallback;
}

function cityKeyFromReverse(payload: NominatimReverse, label: string, countryCode: string) {
  if (payload.osm_type && payload.osm_id) {
    return `osm:${payload.osm_type}:${payload.osm_id}`;
  }
  const country = countryCode || "xx";
  const slug = slugify(label) || "city";
  return `${country}:${slug}`;
}

function bboxFromReverse(payload: NominatimReverse) {
  const bbox = payload.boundingbox;
  if (!bbox || bbox.length < 4) {
    return null;
  }
  const south = Number(bbox[0]);
  const north = Number(bbox[1]);
  const west = Number(bbox[2]);
  const east = Number(bbox[3]);
  if ([south, north, west, east].some((value) => Number.isNaN(value))) {
    return null;
  }
  return { south, north, west, east };
}

async function reverseGeocode(lat: number, lon: number): Promise<NominatimReverse> {
  const url = new URL(`${NOMINATIM_BASE}/reverse`);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("lat", String(lat));
  url.searchParams.set("lon", String(lon));
  url.searchParams.set("zoom", "10");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("polygon_geojson", "1");

  const response = await fetch(url.toString(), {
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`nominatim_http_${response.status}`);
  }

  return await response.json() as NominatimReverse;
}

async function ingestMunicipality(
  admin: ReturnType<typeof createClient>,
  lat: number,
  lon: number,
) {
  const payload = await reverseGeocode(lat, lon);
  const label = municipalityLabel(payload.address, payload.display_name ?? "Unknown city");
  const countryCode = (payload.address?.country_code ?? "").toLowerCase();
  const cityKey = cityKeyFromReverse(payload, label, countryCode);
  const bbox = bboxFromReverse(payload);
  const centerLat = Number(payload.lat ?? lat);
  const centerLon = Number(payload.lon ?? lon);
  const boundaryGeojson = payload.geojson ? JSON.stringify(payload.geojson) : null;

  const { data, error } = await admin.rpc("ingest_territory_municipality_v1", {
    p_city_key: cityKey,
    p_display_name: label,
    p_country_code: countryCode,
    p_admin_level: null,
    p_boundary_geojson: boundaryGeojson,
    p_min_lat: bbox?.south ?? centerLat - 0.15,
    p_min_lon: bbox?.west ?? centerLon - 0.15,
    p_max_lat: bbox?.north ?? centerLat + 0.15,
    p_max_lon: bbox?.east ?? centerLon + 0.15,
    p_center_lat: centerLat,
    p_center_lon: centerLon,
    p_geocode_source: "nominatim",
    p_display_name_override: null,
  });

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

async function runAssignmentBackfill(
  admin: ReturnType<typeof createClient>,
  batchLimit = 1000,
) {
  const { error } = await admin.rpc("backfill_territory_municipality_assignments_v1", {
    p_limit: batchLimit,
  });
  if (error) {
    throw new Error(error.message);
  }
}

Deno.serve(async (req) => {
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const maintenanceSecret = Deno.env.get("TERRITORY_MAINTENANCE_SECRET");
    if (!url || !anon || !service) {
      return new Response(JSON.stringify({ ok: false, error: "missing_env" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization");
    const maintenanceHeader = req.headers.get("x-territory-maintenance-secret");
    const bearerToken = authHeader?.replace(/^Bearer\s+/i, "") ?? "";
    const maintenanceAuthorized =
      maintenanceSecret != null &&
      maintenanceSecret.length > 0 &&
      maintenanceHeader === maintenanceSecret;
    const serviceAuthorized = bearerToken.length > 0 && bearerToken === service;

    const admin = createClient(url, service);
    if (!maintenanceAuthorized && !serviceAuthorized) {
      if (!authHeader) {
        return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }

      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: { user }, error: userError } = await userClient.auth.getUser();
      if (userError || !user) {
        return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const body = await req.json().catch(() => ({}));
    const processed: unknown[] = [];
    const errors: Array<{ bucket_lat?: number; bucket_lon?: number; error: string }> = [];
    const processQueue = body.process_queue !== false;
    const runAssignmentBackfillFlag = body.run_assignment_backfill === true;
    const isBulkOperator = maintenanceAuthorized || serviceAuthorized;
    const requestedItems = Number(body.max_items ?? body.limit ?? 2);
    const maxItems = isBulkOperator
      ? Math.max(1, Math.min(requestedItems, 10))
      : Math.max(1, Math.min(requestedItems, 1));

    if (typeof body.lat === "number" && typeof body.lon === "number") {
      const result = await ingestMunicipality(admin, body.lat, body.lon);
      processed.push(result);
    } else if (processQueue) {
      const { data: queue, error: queueError } = await admin.rpc("list_territory_geocode_queue_v1", {
        p_limit: maxItems,
      });
      if (queueError) {
        throw new Error(queueError.message);
      }

      for (const row of (queue ?? []) as QueueRow[]) {
        try {
          const result = await ingestMunicipality(admin, row.sample_lat, row.sample_lon);
          processed.push(result);
        } catch (error) {
          const message = error instanceof Error ? error.message : "unknown";
          errors.push({
            bucket_lat: row.bucket_lat,
            bucket_lon: row.bucket_lon,
            error: message,
          });
          await admin.rpc("mark_territory_geocode_queue_error_v1", {
            p_bucket_lat: row.bucket_lat,
            p_bucket_lon: row.bucket_lon,
            p_error: message,
          });
        }
        await sleep(1100);
      }
    }

    if (processed.length > 0 || runAssignmentBackfillFlag) {
      await runAssignmentBackfill(admin);
    }

    return new Response(JSON.stringify({
      ok: true,
      processed,
      errors,
      max_items: maxItems,
      run_assignment_backfill: runAssignmentBackfillFlag,
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
