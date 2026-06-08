export function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function appRedirectUrl(provider: string, status: string, message?: string): string {
  const base = "com.davidgomez.Liftr://wearable-callback";
  const params = new URLSearchParams({ provider, status });
  if (message) params.set("message", message);
  return `${base}?${params.toString()}`;
}

export async function signState(payload: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const hex = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${payload}.${hex}`;
}

export async function verifyState(state: string, secret: string): Promise<Record<string, string> | null> {
  const lastDot = state.lastIndexOf(".");
  if (lastDot <= 0) return null;
  const payload = state.slice(0, lastDot);
  const sig = state.slice(lastDot + 1);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const expectedHex = Array.from(new Uint8Array(expected))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  if (expectedHex !== sig) return null;
  const params = new URLSearchParams(payload);
  const out: Record<string, string> = {};
  for (const [k, v] of params.entries()) out[k] = v;
  return out;
}
