export type RoutePoint = {
  lat: number;
  lon: number;
  alt: number | null;
  ts: string | null;
};

const MAX_STORED_COORDINATES = 2000;

export function parseGpxTrackPoints(gpx: string): RoutePoint[] {
  const points: RoutePoint[] = [];
  const trkptRegex = /<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"[^>]*>([\s\S]*?)<\/trkpt>/gi;
  let match: RegExpExecArray | null;
  while ((match = trkptRegex.exec(gpx)) !== null) {
    const lat = Number(match[1]);
    const lon = Number(match[2]);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const inner = match[3] ?? "";
    const eleMatch = /<ele>([^<]+)<\/ele>/i.exec(inner);
    const timeMatch = /<time>([^<]+)<\/time>/i.exec(inner);
    const alt = eleMatch ? Number(eleMatch[1]) : null;
    points.push({
      lat,
      lon,
      alt: alt != null && Number.isFinite(alt) ? alt : null,
      ts: timeMatch?.[1]?.trim() ?? null,
    });
  }
  return decimateRoutePoints(points);
}

export function decimateRoutePoints(points: RoutePoint[]): RoutePoint[] {
  if (points.length <= MAX_STORED_COORDINATES) return points;
  const maxPoints = MAX_STORED_COORDINATES;
  const n = points.length;
  const out: RoutePoint[] = [];
  const denom = maxPoints - 1;
  for (let i = 0; i < maxPoints; i += 1) {
    const idx = Math.floor((i * (n - 1)) / denom);
    out.push(points[idx]);
  }
  return out;
}

export function mapGarminActivityType(activityType: string | null | undefined): string | null {
  const normalized = (activityType ?? "").trim().toUpperCase();
  switch (normalized) {
    case "RUNNING":
    case "TRAIL_RUNNING":
    case "TREADMILL_RUNNING":
      return normalized === "TREADMILL_RUNNING" ? "treadmill" : "run";
    case "WALKING":
      return "walk";
    case "HIKING":
      return "hike";
    case "CYCLING":
    case "ROAD_BIKING":
    case "MOUNTAIN_BIKING":
    case "GRAVEL_CYCLING":
      return "bike";
    case "INDOOR_CYCLING":
      return "indoor_cycling";
    case "SWIMMING":
    case "OPEN_WATER_SWIMMING":
      return normalized === "OPEN_WATER_SWIMMING" ? "swim_open_water" : "swim_pool";
    case "ROWING":
      return "rowerg";
    default:
      return null;
  }
}
