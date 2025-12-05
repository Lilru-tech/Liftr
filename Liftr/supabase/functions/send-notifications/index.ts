import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@4.15.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SERVICE_JSON = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!);

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const projectId = SERVICE_JSON.project_id;
const clientEmail = SERVICE_JSON.client_email;
const privateKey = SERVICE_JSON.private_key;
const tokenUri = SERVICE_JSON.token_uri;

Deno.serve(async () => {

  const { data: notifs } = await supabase
    .from("notifications")
    .select("*")
    .is("sent_at", null)
    .order("created_at")
    .limit(50);

  if (!notifs?.length) return new Response("No pending", { status: 200 });

  for (const notif of notifs) {
    try {
      const { data: profile } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("user_id", notif.user_id)
        .maybeSingle();

      if (!profile?.fcm_token) {
        await markError(notif.id, "no_token");
        continue;
      }

        const ok = await sendToFcmV1(profile.fcm_token, notif);
        if (ok) {
          await markSent(notif.id);
        }
    } catch (e) {
      await markError(notif.id, "exception: " + e);
    }
  }

  return new Response("done");
});

async function getAccessToken() {
  const now = Math.floor(Date.now() / 1000);

  const jwt = await new SignJWT({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .sign(await importPKCS8(privateKey, "RS256"));

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  return (await res.json()).access_token;
}

function buildDataPayload(notif: any): Record<string, string> {
  const raw = notif.data || {};
  const result: Record<string, string> = {};

  if (notif.type) {
    result.type = String(notif.type);
  }

  for (const [key, value] of Object.entries(raw)) {
    if (value === null || value === undefined) continue;

    if (typeof value === "string") {
      result[key] = value;
    } else if (typeof value === "number" || typeof value === "boolean") {
      result[key] = String(value);
    } else {
      result[key] = JSON.stringify(value);
    }
  }

  return result;
}

async function sendToFcmV1(token: string, notif: any): Promise<boolean> {
  try {
    const access = await getAccessToken();

      const payload = {
        message: {
          token,
          notification: {
            title: notif.title,
            body: notif.body,
          },
          data: buildDataPayload(notif),
        },
      };

    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const text = await res.text();
    console.log("🔔 FCM status:", res.status, text);

    if (!res.ok) {
      await markError(
        notif.id,
        `fcm_${res.status}: ${text.slice(0, 200)}`
      );
      return false;
    }

    return true;
  } catch (e) {
    console.error("🔥 FCM exception:", e);
    await markError(
      notif.id,
      `exception: ${e instanceof Error ? e.message : String(e)}`
    );
    return false;
  }
}

async function markSent(id: number) {
  await supabase.from("notifications")
    .update({ sent_at: new Date().toISOString(), send_error: null })
    .eq("id", id);
}

async function markError(id: number, msg: string) {
  await supabase.from("notifications")
    .update({ send_error: msg })
    .eq("id", id);
}
