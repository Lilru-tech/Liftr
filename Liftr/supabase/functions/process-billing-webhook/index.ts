import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { upsertUserSubscription } from "../_shared/subscription-upsert.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BILLING_WEBHOOK_SECRET = Deno.env.get("BILLING_WEBHOOK_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const ALLOWED_PROVIDERS = new Set(["apple", "google"]);
const ALLOWED_STATUSES = new Set(["active", "trialing", "canceled", "expired"]);

type BillingWebhookPayload = {
  user_id: string;
  status: string;
  provider: string;
  original_transaction_id: string;
  expires_at: string;
};

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function encodeSecret(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

async function secretsEqual(a: string, b: string): Promise<boolean> {
  const aBytes = encodeSecret(a);
  const bBytes = encodeSecret(b);
  if (aBytes.length !== bBytes.length) {
    return false;
  }
  return crypto.subtle.timingSafeEqual(aBytes, bBytes);
}

function extractSignatureToken(req: Request): string | null {
  const headerSig = req.headers.get("X-Billing-Signature")?.trim();
  if (headerSig) {
    return headerSig;
  }
  const auth = req.headers.get("Authorization")?.trim() ?? "";
  if (auth.toLowerCase().startsWith("bearer ")) {
    return auth.slice(7).trim();
  }
  return null;
}

function parsePayload(raw: unknown): BillingWebhookPayload {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("invalid payload");
  }
  const body = raw as Record<string, unknown>;
  const userId = String(body.user_id ?? "").trim();
  const status = String(body.status ?? "").trim().toLowerCase();
  const provider = String(body.provider ?? "").trim().toLowerCase();
  const originalTransactionId = String(body.original_transaction_id ?? "").trim();
  const expiresAtRaw = String(body.expires_at ?? "").trim();

  if (!userId) {
    throw new Error("user_id is required");
  }
  if (!status || !ALLOWED_STATUSES.has(status)) {
    throw new Error("status must be active, trialing, canceled, or expired");
  }
  if (!provider || !ALLOWED_PROVIDERS.has(provider)) {
    throw new Error("provider must be apple or google");
  }
  if (!originalTransactionId) {
    throw new Error("original_transaction_id is required");
  }
  if (!expiresAtRaw) {
    throw new Error("expires_at is required");
  }

  const expiresAt = new Date(expiresAtRaw);
  if (Number.isNaN(expiresAt.getTime())) {
    throw new Error("expires_at must be a valid ISO-8601 timestamp");
  }

  return {
    user_id: userId,
    status,
    provider,
    original_transaction_id: originalTransactionId,
    expires_at: expiresAt.toISOString(),
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  if (!BILLING_WEBHOOK_SECRET) {
    return jsonResponse({ error: "webhook secret not configured" }, 500);
  }

  const token = extractSignatureToken(req);
  if (!token) {
    return jsonResponse({ error: "missing signature" }, 401);
  }

  const signatureValid = await secretsEqual(token, BILLING_WEBHOOK_SECRET);
  if (!signatureValid) {
    return jsonResponse({ error: "invalid signature" }, 401);
  }

  let payload: BillingWebhookPayload;
  try {
    const raw = await req.json();
    payload = parsePayload(raw);
  } catch (e) {
    const message = e instanceof Error ? e.message : "invalid payload";
    return jsonResponse({ error: message }, 400);
  }

  const { error } = await upsertUserSubscription(supabase, payload);

  if (error) {
    console.error("user_subscriptions upsert failed:", error);
    return jsonResponse({ error }, 500);
  }

  return jsonResponse({ ok: true }, 200);
});
