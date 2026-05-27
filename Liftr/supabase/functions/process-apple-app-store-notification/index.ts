import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { upsertUserSubscription } from "../_shared/subscription-upsert.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APPLE_PREMIUM_PRODUCT_ID = Deno.env.get("APPLE_PREMIUM_PRODUCT_ID") ??
  "com.liftr.premium.monthly";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

type AppleNotificationPayload = {
  notificationType?: string;
  subtype?: string;
  data?: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};

type AppleTransactionPayload = {
  originalTransactionId?: string;
  productId?: string;
  expiresDate?: number;
  appAccountToken?: string;
};

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function decodeJwsPayload<T>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new Error("invalid jws");
  }
  let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const pad = payload.length % 4;
  if (pad > 0) {
    payload += "=".repeat(4 - pad);
  }
  const json = atob(payload);
  return JSON.parse(json) as T;
}

function mapAppleStatus(
  notificationType: string,
  subtype: string | undefined,
  expiresAtMs: number | null,
): string {
  const now = Date.now();
  const type = notificationType.toUpperCase();
  const sub = (subtype ?? "").toUpperCase();

  const hardExpireTypes = new Set([
    "EXPIRED",
    "GRACE_PERIOD_EXPIRED",
    "REFUND",
    "REVOKE",
  ]);
  if (hardExpireTypes.has(type)) {
    return "expired";
  }

  if (type === "DID_CHANGE_RENEWAL_STATUS" && sub === "AUTO_RENEW_DISABLED") {
    if (expiresAtMs != null && expiresAtMs > now) {
      return "active";
    }
    return "expired";
  }

  if (expiresAtMs != null && expiresAtMs > now) {
    if (type === "SUBSCRIBED" && sub === "INITIAL_BUY") {
      return "trialing";
    }
    return "active";
  }

  return "expired";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid json" }, 400);
  }

  const signedPayload = typeof body.signedPayload === "string"
    ? body.signedPayload
    : null;
  if (!signedPayload) {
    return jsonResponse({ error: "signedPayload required" }, 400);
  }

  let notification: AppleNotificationPayload;
  try {
    notification = decodeJwsPayload<AppleNotificationPayload>(signedPayload);
  } catch (e) {
    const message = e instanceof Error ? e.message : "decode failed";
    return jsonResponse({ error: message }, 400);
  }

  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (!signedTransactionInfo) {
    return jsonResponse({ ok: true, skipped: "no_transaction_info" }, 200);
  }

  let transaction: AppleTransactionPayload;
  try {
    transaction = decodeJwsPayload<AppleTransactionPayload>(signedTransactionInfo);
  } catch (e) {
    const message = e instanceof Error ? e.message : "transaction decode failed";
    return jsonResponse({ error: message }, 400);
  }

  const productId = String(transaction.productId ?? "").trim();
  if (productId && productId !== APPLE_PREMIUM_PRODUCT_ID) {
    return jsonResponse({ ok: true, skipped: "other_product" }, 200);
  }

  const originalTransactionId = String(transaction.originalTransactionId ?? "").trim();
  if (!originalTransactionId) {
    return jsonResponse({ error: "missing originalTransactionId" }, 400);
  }

  const userId = String(transaction.appAccountToken ?? "").trim().toLowerCase();
  if (!userId) {
    console.warn(
      "apple notification without appAccountToken; originalTransactionId=",
      originalTransactionId,
    );
    return jsonResponse({ ok: true, skipped: "no_app_account_token" }, 200);
  }

  const expiresAtMs = typeof transaction.expiresDate === "number"
    ? transaction.expiresDate
    : null;
  const expiresAtIso = expiresAtMs != null
    ? new Date(expiresAtMs).toISOString()
    : new Date(0).toISOString();

  const status = mapAppleStatus(
    String(notification.notificationType ?? ""),
    notification.subtype,
    expiresAtMs,
  );

  const { error } = await upsertUserSubscription(supabase, {
    user_id: userId,
    status,
    provider: "apple",
    original_transaction_id: originalTransactionId,
    expires_at: expiresAtIso,
  });

  if (error) {
    console.error("user_subscriptions upsert failed:", error);
    return jsonResponse({ error }, 500);
  }

  return jsonResponse({
    ok: true,
    user_id: userId,
    status,
    original_transaction_id: originalTransactionId,
  }, 200);
});
