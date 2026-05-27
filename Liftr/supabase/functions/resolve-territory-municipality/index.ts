import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const NOMINATIM_BASE = "https://nominatim.openstreetmap.org";
const USER_AGENT = "Liftr/1.0 (territory-municipality-resolve)";
const MIN_MUNICIPALITY_AREA_M2 = 5_000_000;
const REVERSE_ZOOM_SUBURB = 14;
const REVERSE_ZOOM_CITY = 10;

type QueueRow = {
  bucket_lat: number;
  bucket_lon: number;
  sample_lat: number;
  sample_lon: number;
  attempts: number;
};

type NominatimPlace = {
  place_id?: number;
  osm_type?: string;
  osm_id?: number;
  lat?: string;
  lon?: string;
  display_name?: string;
  boundingbox?: string[];
  geojson?: { type?: string; coordinates?: unknown };
  address?: Record<string, string | undefined>;
  type?: string;
  category?: string;
};

type IngestRequest = {
  lat: number;
  lon: number;
  bucket_lat?: number;
  bucket_lon?: number;
};

type MunicipalityResolution = {
  payload: NominatimPlace;
  cityKey: string;
  label: string;
  countryCode: string;
  adminLevel: number | null;
  geocodeSource: string;
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

function cityKeyFromPlace(payload: NominatimPlace, label: string, countryCode: string) {
  if (payload.osm_type && payload.osm_id) {
    return `osm:${payload.osm_type}:${payload.osm_id}`;
  }
  const country = countryCode || "xx";
  const slug = slugify(label) || "city";
  return `${country}:${slug}`;
}

function bboxFromPlace(payload: NominatimPlace) {
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

function approximateBoundaryAreaM2(payload: NominatimPlace) {
  const bbox = bboxFromPlace(payload);
  if (!bbox) {
    return 0;
  }
  const latMid = (bbox.south + bbox.north) / 2;
  const latM = 111_320;
  const lonM = 111_320 * Math.cos((latMid * Math.PI) / 180);
  return Math.abs(bbox.north - bbox.south) * latM * Math.abs(bbox.east - bbox.west) * lonM;
}

function isAdministrativeBoundary(payload: NominatimPlace) {
  return payload.category === "boundary" && payload.type === "administrative";
}

async function nominatimFetch(path: string, params: Record<string, string>) {
  const url = new URL(`${NOMINATIM_BASE}${path}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url.toString(), {
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`nominatim_http_${response.status}`);
  }
  return await response.json();
}

async function reverseGeocode(
  lat: number,
  lon: number,
  includePolygon: boolean,
  zoom = REVERSE_ZOOM_SUBURB,
): Promise<NominatimPlace> {
  const params: Record<string, string> = {
    format: "jsonv2",
    lat: String(lat),
    lon: String(lon),
    zoom: String(zoom),
    addressdetails: "1",
  };
  if (includePolygon) {
    params.polygon_geojson = "1";
  }
  return await nominatimFetch("/reverse", params) as NominatimPlace;
}

async function lookupOsmRelation(osmId: number): Promise<NominatimPlace | null> {
  const rows = await nominatimFetch("/lookup", {
    format: "jsonv2",
    osm_ids: `R${osmId}`,
    polygon_geojson: "1",
  }) as NominatimPlace[];
  return rows[0] ?? null;
}

function countryNameForSearch(
  countryCode: string,
  address: Record<string, string | undefined> | undefined,
) {
  const fromAddress = address?.country?.trim();
  if (fromAddress) {
    return fromAddress;
  }
  if (countryCode === "es") {
    return "Spain";
  }
  return countryCode.toUpperCase();
}

async function searchMunicipality(
  label: string,
  countryCode: string,
  address?: Record<string, string | undefined>,
): Promise<NominatimPlace | null> {
  const countryName = countryNameForSearch(countryCode, address);
  const query = countryName.length > 0 ? `${label}, ${countryName}` : label;
  const rows = await nominatimFetch("/search", {
    format: "jsonv2",
    q: query,
    featuretype: "city",
    polygon_geojson: "1",
    limit: "5",
    addressdetails: "1",
  }) as NominatimPlace[];

  const ranked = rows
    .filter((row) => row.osm_type === "relation" && row.osm_id)
    .sort((left, right) => approximateBoundaryAreaM2(right) - approximateBoundaryAreaM2(left));

  return ranked[0] ?? null;
}

function municipalityTownName(address: Record<string, string | undefined> | undefined) {
  const candidates = [
    address?.city,
    address?.town,
    address?.village,
    address?.municipality,
  ];
  for (const candidate of candidates) {
    if (candidate && candidate.trim().length > 0) {
      return candidate.trim();
    }
  }
  return null;
}

async function findExistingMunicipalityCityKey(
  admin: ReturnType<typeof createClient>,
  label: string,
  countryCode: string,
) {
  let query = admin
    .from("territory_municipalities")
    .select("city_key, total_capture_cells")
    .ilike("display_name", label);
  if (countryCode) {
    query = query.eq("country_code", countryCode);
  }
  const { data, error } = await query
    .order("total_capture_cells", { ascending: false })
    .limit(1);
  if (error || !data?.[0]?.city_key) {
    return null;
  }
  return data[0].city_key as string;
}

async function resolveCityKey(
  admin: ReturnType<typeof createClient>,
  payload: NominatimPlace,
  label: string,
  countryCode: string,
) {
  const payloadKey = cityKeyFromPlace(payload, label, countryCode);
  if (approximateBoundaryAreaM2(payload) >= MIN_MUNICIPALITY_AREA_M2) {
    return payloadKey;
  }

  const existing = await findExistingMunicipalityCityKey(admin, label, countryCode);
  if (existing) {
    return existing;
  }

  return payloadKey;
}

async function upgradeToMunicipalityBoundary(
  admin: ReturnType<typeof createClient>,
  payload: NominatimPlace,
  label: string,
  countryCode: string,
): Promise<NominatimPlace> {
  const bboxArea = approximateBoundaryAreaM2(payload);
  const townName = municipalityTownName(payload.address) ?? label;
  const shouldUpgrade = bboxArea < MIN_MUNICIPALITY_AREA_M2 || !isAdministrativeBoundary(payload);

  if (!shouldUpgrade) {
    return payload;
  }

  const forward = await searchMunicipality(townName, countryCode, payload.address);
  if (forward && approximateBoundaryAreaM2(forward) >= MIN_MUNICIPALITY_AREA_M2) {
    return forward;
  }

  if (bboxArea < MIN_MUNICIPALITY_AREA_M2) {
    const cityReverse = await reverseGeocode(
      Number(payload.lat ?? 0),
      Number(payload.lon ?? 0),
      true,
      REVERSE_ZOOM_CITY,
    );
    if (approximateBoundaryAreaM2(cityReverse) > bboxArea) {
      return cityReverse;
    }
  }

  return payload;
}

async function resolveMunicipality(
  admin: ReturnType<typeof createClient>,
  lat: number,
  lon: number,
): Promise<MunicipalityResolution> {
  let payload: NominatimPlace;
  try {
    payload = await reverseGeocode(lat, lon, true, REVERSE_ZOOM_SUBURB);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    console.error("[resolve-territory-municipality] nominatim polygon failed", { lat, lon, error: message });
    payload = await reverseGeocode(lat, lon, false, REVERSE_ZOOM_SUBURB);
  }

  const label = municipalityLabel(payload.address, payload.display_name ?? "Unknown city");
  const countryCode = (payload.address?.country_code ?? "").toLowerCase();
  payload = await upgradeToMunicipalityBoundary(admin, payload, label, countryCode);

  const resolvedLabel = municipalityLabel(payload.address, payload.display_name ?? label);
  const cityKey = await resolveCityKey(admin, payload, resolvedLabel, countryCode);

  return {
    payload,
    cityKey,
    label: resolvedLabel,
    countryCode,
    adminLevel: null,
    geocodeSource: "nominatim",
  };
}

async function resolveMunicipalityFromOsmRelation(
  admin: ReturnType<typeof createClient>,
  osmRelationId: number,
): Promise<MunicipalityResolution> {
  const payload = await lookupOsmRelation(osmRelationId);
  if (!payload) {
    throw new Error("osm_relation_not_found");
  }

  const label = municipalityLabel(payload.address, payload.display_name ?? "Unknown city");
  const countryCode = (payload.address?.country_code ?? "es").toLowerCase();
  const upgraded = await upgradeToMunicipalityBoundary(admin, payload, label, countryCode);
  const resolvedLabel = municipalityLabel(upgraded.address, upgraded.display_name ?? label);
  const cityKey = `osm:relation:${osmRelationId}`;

  return {
    payload: upgraded,
    cityKey,
    label: resolvedLabel,
    countryCode,
    adminLevel: null,
    geocodeSource: "nominatim_lookup",
  };
}

async function ingestResolvedMunicipality(
  admin: ReturnType<typeof createClient>,
  resolution: MunicipalityResolution,
  request: IngestRequest,
) {
  const { lat, lon, bucket_lat: bucketLat, bucket_lon: bucketLon } = request;
  const payload = resolution.payload;
  const bbox = bboxFromPlace(payload);
  const centerLat = Number(payload.lat ?? lat);
  const centerLon = Number(payload.lon ?? lon);
  const boundaryGeojson = payload.geojson ? JSON.stringify(payload.geojson) : null;

  const ingestArgs = {
    p_city_key: resolution.cityKey,
    p_display_name: resolution.label,
    p_country_code: resolution.countryCode,
    p_admin_level: resolution.adminLevel,
    p_boundary_geojson: boundaryGeojson,
    p_min_lat: bbox?.south ?? centerLat - 0.15,
    p_min_lon: bbox?.west ?? centerLon - 0.15,
    p_max_lat: bbox?.north ?? centerLat + 0.15,
    p_max_lon: bbox?.east ?? centerLon + 0.15,
    p_center_lat: centerLat,
    p_center_lon: centerLon,
    p_geocode_source: resolution.geocodeSource,
    p_display_name_override: null,
    p_bucket_lat: bucketLat ?? null,
    p_bucket_lon: bucketLon ?? null,
  };

  const { data, error } = await admin.rpc("ingest_territory_municipality_v1", ingestArgs);

  if (error) {
    if (boundaryGeojson) {
      console.error("[resolve-territory-municipality] ingest polygon failed, retrying bbox", {
        lat,
        lon,
        cityKey: resolution.cityKey,
        error: error.message,
      });
      const { data: retryData, error: retryError } = await admin.rpc("ingest_territory_municipality_v1", {
        ...ingestArgs,
        p_boundary_geojson: null,
      });
      if (retryError) {
        throw new Error(retryError.message);
      }
      return retryData;
    }
    throw new Error(error.message);
  }

  return data;
}

async function ingestMunicipality(
  admin: ReturnType<typeof createClient>,
  request: IngestRequest,
) {
  const resolution = await resolveMunicipality(admin, request.lat, request.lon);
  return ingestResolvedMunicipality(admin, resolution, request);
}

async function mergeTerritoryMunicipalityKeys(
  admin: ReturnType<typeof createClient>,
  fromCityKey: string,
  toCityKey: string,
) {
  const { data, error } = await admin.rpc("merge_territory_municipality_keys_v1", {
    p_from_city_key: fromCityKey,
    p_to_city_key: toCityKey,
  });
  if (error) {
    throw new Error(error.message);
  }
  return data;
}

async function runAssignmentBackfill(
  admin: ReturnType<typeof createClient>,
  batchLimit = 200,
) {
  const { data, error } = await admin.rpc("backfill_territory_municipality_assignments_v1", {
    p_limit: batchLimit,
  });
  if (error) {
    throw new Error(error.message);
  }
  return data as { ok?: boolean; updated?: number; has_more?: boolean } | null;
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
    const errors: Array<{ bucket_lat?: number; bucket_lon?: number; lat?: number; lon?: number; error: string }> = [];
    let assignmentBackfill: { ok?: boolean; updated?: number; has_more?: boolean } | null = null;
    const isBulkOperator = maintenanceAuthorized || serviceAuthorized;
    const requestedItems = Number(body.max_items ?? body.limit ?? 2);
    const maxItems = isBulkOperator
      ? Math.max(1, Math.min(requestedItems, 10))
      : Math.max(1, Math.min(requestedItems, 1));

    if (!isBulkOperator) {
      if (typeof body.lat === "number" || typeof body.lon === "number") {
        return new Response(JSON.stringify({ ok: false, error: "forbidden_point_ingest" }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (body.run_assignment_backfill === true) {
        return new Response(JSON.stringify({ ok: false, error: "forbidden_assignment_backfill" }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (body.process_queue === false) {
        return new Response(JSON.stringify({ ok: false, error: "process_queue_required" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (typeof body.osm_relation_id === "number" || typeof body.merge_from_city_key === "string") {
        return new Response(JSON.stringify({ ok: false, error: "forbidden_maintenance_repair" }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const processQueue = body.process_queue !== false;
    const runAssignmentBackfillFlag = isBulkOperator && body.run_assignment_backfill === true;

    if (isBulkOperator && typeof body.osm_relation_id === "number") {
      try {
        const resolution = await resolveMunicipalityFromOsmRelation(admin, body.osm_relation_id);
        const result = await ingestResolvedMunicipality(admin, resolution, {
          lat: Number(resolution.payload.lat ?? 41.39),
          lon: Number(resolution.payload.lon ?? 2.17),
        });
        processed.push(result);
        if (typeof body.merge_from_city_key === "string" && body.merge_from_city_key.length > 0) {
          const mergeResult = await mergeTerritoryMunicipalityKeys(
            admin,
            body.merge_from_city_key,
            resolution.cityKey,
          );
          processed.push(mergeResult);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : "unknown";
        errors.push({ error: message });
      }
    } else if (isBulkOperator && typeof body.lat === "number" && typeof body.lon === "number") {
      try {
        const result = await ingestMunicipality(admin, {
          lat: body.lat,
          lon: body.lon,
          bucket_lat: typeof body.bucket_lat === "number" ? body.bucket_lat : undefined,
          bucket_lon: typeof body.bucket_lon === "number" ? body.bucket_lon : undefined,
        });
        console.log("[resolve-territory-municipality] point ingest ok", result);
        processed.push(result);
      } catch (error) {
        const message = error instanceof Error ? error.message : "unknown";
        console.error("[resolve-territory-municipality] point ingest failed", {
          lat: body.lat,
          lon: body.lon,
          bucket_lat: body.bucket_lat,
          bucket_lon: body.bucket_lon,
          error: message,
        });
        errors.push({
          lat: body.lat,
          lon: body.lon,
          bucket_lat: typeof body.bucket_lat === "number" ? body.bucket_lat : undefined,
          bucket_lon: typeof body.bucket_lon === "number" ? body.bucket_lon : undefined,
          error: message,
        });
      }
    } else if (processQueue) {
      const { data: queue, error: queueError } = await admin.rpc("list_territory_geocode_queue_v1", {
        p_limit: maxItems,
      });
      if (queueError) {
        throw new Error(queueError.message);
      }

      for (const row of (queue ?? []) as QueueRow[]) {
        try {
          const result = await ingestMunicipality(admin, {
            lat: row.sample_lat,
            lon: row.sample_lon,
            bucket_lat: Number(row.bucket_lat),
            bucket_lon: Number(row.bucket_lon),
          });
          console.log("[resolve-territory-municipality] queue ingest ok", {
            bucket_lat: row.bucket_lat,
            bucket_lon: row.bucket_lon,
            result,
          });
          processed.push(result);
        } catch (error) {
          const message = error instanceof Error ? error.message : "unknown";
          console.error("[resolve-territory-municipality] queue ingest failed", {
            bucket_lat: row.bucket_lat,
            bucket_lon: row.bucket_lon,
            lat: row.sample_lat,
            lon: row.sample_lon,
            error: message,
          });
          errors.push({
            bucket_lat: row.bucket_lat,
            bucket_lon: row.bucket_lon,
            lat: row.sample_lat,
            lon: row.sample_lon,
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

    if (runAssignmentBackfillFlag) {
      try {
        assignmentBackfill = await runAssignmentBackfill(admin);
        console.log("[resolve-territory-municipality] assignment backfill ok", assignmentBackfill);
      } catch (error) {
        const message = error instanceof Error ? error.message : "unknown";
        console.error("[resolve-territory-municipality] assignment backfill failed", { error: message });
        errors.push({ error: message });
      }
    }

    return new Response(JSON.stringify({
      ok: true,
      processed,
      errors,
      assignment_backfill: assignmentBackfill,
      max_items: maxItems,
      run_assignment_backfill: runAssignmentBackfillFlag,
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    console.error("[resolve-territory-municipality] fatal", { error: message });
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
